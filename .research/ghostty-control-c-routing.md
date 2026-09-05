# macOS Ghostty Control-C routing: `NSEvent` to PTY

**Research scope.** This report traces the current macOS implementation in the pinned Ghostty source tree at `.agents/references/ghostty`, commit `3c1ef5b32fc5ea6b93d28493fabf193f595139cf` (`ghostty-org/ghostty`). It uses Ghostty source as the authority for Ghostty behavior and Apple documentation only for AppKit's dispatch contract. No production code was changed.

## Executive conclusion

The Ghostty source audit established that Fission's existing AppKit-to-Ghostty key path is correct. Runtime inspection then located the observed Fission failure **after** key encoding: the installed app was reconnecting to a persistent `FissionExecution` daemon that had started before Fission's controlling-terminal fix. Its hosted PTYs returned `ENOTTY` for foreground-process-group queries, so the terminal discipline consumed byte `0x03` without delivering `SIGINT` to zsh. Because the daemon socket was still protocol version 1, replacing the app and helper executable did not replace the already-running daemon.

The durable fix is to bump `TerminalExecutionProtocol.version` to 2. This selects a new versioned socket and prevents an upgraded client from reconnecting to the incompatible helper. The earlier Fission-specific `performKeyEquivalent` interception for bare Control-C is unnecessary and should be removed: it changes Ghostty's binding/menu behavior without addressing the faulty PTY.

A physical **Control-C** is not correctly modeled as “send `event.characters` to the PTY.” In Ghostty's macOS frontend it is a complete key event:

```text
physical C key (macOS virtual keycode 0x08)
  + NSEvent modifierFlags = Control
  + layout-derived text normalized to "c"
  + consumed_mods = none
  + unshifted_codepoint = U+0063
  + composing state
       │
       ▼
performKeyEquivalent (preflight; normally no Ctrl-C binding)
       │ false
       ▼
AppKit first-responder / text-input dispatch
       │
       ▼
SurfaceView.keyDown → interpretKeyEvents → keyAction
       │
       ▼
ghostty_surface_key → Surface.keyCallback
       │
       ├─ binding resolution first
       └─ key encoder: Ctrl + "c" → one byte 0x03
                                │
                                ▼
                     IO mailbox → writer thread → PTY master
```

In the ordinary legacy keyboard mode, the PTY receives exactly **`0x03`**. The kernel terminal discipline, not Ghostty, normally interprets that byte as `VINTR` and sends `SIGINT` to the foreground process group when `ISIG` is enabled. In raw mode or with changed termios settings, the child can instead read the byte. Therefore an embedder should route the original key event through Ghostty exactly once; it should neither send text/paste data nor call `kill(SIGINT)` itself.

**Command-C is deliberately different.** Ghostty's macOS defaults define Command-C as a `performable:` `copy_to_clipboard` binding. It is offered in `performKeyEquivalent`, sent through Ghostty's binding engine, and consumed only at the core-binding level when a selection can actually be copied. If it falls through to encoding, macOS legacy encoding explicitly emits no text for Command-modified keys. It is never the terminal interrupt byte.

## 1. AppKit dispatch: why `performKeyEquivalent`, `keyDown`, and `doCommand` all matter

Apple documents the path in two stages:

1. `NSApplication.sendEvent` recognizes a potential key equivalent from modifier flags and sends `performKeyEquivalent:` to the key window. `NSWindow` walks its view hierarchy until a view returns `YES`; if none does, AppKit tries menu-bar menus. An unhandled event can then be dispatched to the key window's first responder as `keyDown:`. A custom key-equivalent handler should inspect `charactersIgnoringModifiers` and return `YES` only after handling the event. [Apple, *Handling Key Events*, “Handling Key Equivalents”](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html#//apple_ref/doc/uid/10000060i-CH7-SW6)
2. A text-input view's `keyDown:` normally calls `interpretKeyEvents:`. The text input manager consults key-binding dictionaries and calls either `doCommandBySelector:` for a bound command, `insertText:` for committed text, or marked-text methods for composition. The default `doCommandBySelector:` invokes a supported action or passes it up the responder chain. [Apple, *Handling Key Events*, “Handling Keyboard Actions”](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html#//apple_ref/doc/uid/10000060i-CH7-SW3)

Ghostty conforms to that model but adds a workaround for AppKit command redirection:

- `SurfaceView` accepts first responder status. (`macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`, lines 224-225, symbol `acceptsFirstResponder`.)
- `performKeyEquivalent` only handles key-down events and only while the surface's own `focused` state is true. It preflights the event against Ghostty's current binding set before deciding whether to intercept it. (`SurfaceView_AppKit.swift`, lines 1304-1327, symbol `performKeyEquivalent(with:)`.)
- For an unbound Control- or Command-modified event, it stores the event timestamp and initially returns `false`, allowing AppKit's standard route. If the same event returns through `performKeyEquivalent`, it synthesizes a key-down event and calls `keyDown`; special cases also normalize Control-Return and Control-/ to avoid AppKit defaults/beeps. (`SurfaceView_AppKit.swift`, lines 1350-1425.)
- The extensive `lastPerformKeyEvent` comment names the concrete hazard: AppKit may transform an event after the first `performKeyEquivalent` into `doCommand` before Ghostty's `keyDown` runs (Command-Period → `cancel:` is the example). Ghostty identifies redispatch by nonzero timestamp. (`SurfaceView_AppKit.swift`, lines 1276-1302.)
- Ghostty's `doCommand(by:)` intentionally does not perform text actions or call `super`; if its current event matches the saved timestamp, it calls `NSApp.sendEvent(current)` so the same event can re-enter Ghostty and eventually reach `keyDown`. This both prevents an NSBeep and preserves otherwise intercepted Command/Control input. (`SurfaceView_AppKit.swift`, lines 2116-2127, symbol `doCommand(by:)`.)

### What this means for Control-C

On the standard macOS layout, the physical C key has virtual keycode **`0x0008`** (`macos/Sources/Ghostty/Ghostty.Input.swift`, lines 1043-1083, symbol `Input.Key.keyCode`, case `.c` at line 1081). A normal bare Control-C key-down has:

| Field | Control-C | Command-C | Why it matters |
|---|---:|---:|---|
| `type` | `.keyDown` | `.keyDown` | Only down/repeat can bind/encode in the legacy path. |
| `keyCode` | `0x08` | `0x08` | Physical, layout-independent identity used to derive Ghostty `.key_c`. |
| `modifierFlags` | `.control` (plus non-shortcut flags such as caps/device bits) | `.command` | Becomes Ghostty `ctrl` versus `super`; sided device bits are retained. |
| `characters` | commonly U+0003 on a US input source | commonly `"c"` | AppKit/layout output; must not alone define physical identity or terminal bytes. |
| `charactersIgnoringModifiers` | `"c"` on the standard layout | `"c"` | Useful for key-equivalent matching, not sufficient as the core event. |
| Ghostty `text` | normalized `"c"` on the ordinary non-IME fallback | `"c"` | Lets core encode Ctrl-C itself. |
| Ghostty `mods` | `ctrl` | `super` | Controls binding and protocol encoding. |
| Ghostty `consumed_mods` | none | none | Ghostty assumes Control and Command never participate in producing text. |
| `unshifted_codepoint` | U+0063 | U+0063 | Obtained by applying no modifiers, independent of the control character in `characters`. |

The precise `characters` value is input-source/AppKit dependent; the stable facts are the physical keycode, modifier, and Ghostty's normalization. Apple explicitly warns that an `NSEvent` key value is a string, may contain multiple characters, and may be empty for a dead key. [Apple, *Handling Key Events*, “Getting Characters from a Key Event”](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html#//apple_ref/doc/uid/10000060i-CH7-SW1)

Ghostty constructs those core fields as follows:

- `ghosttyKeyEvent` copies `keyCode`; maps AppKit flags to Ghostty modifiers, including right-side device masks; removes Control and Command from `consumed_mods`; and computes the unshifted codepoint with `characters(byApplyingModifiers: [])`, explicitly avoiding `charactersIgnoringModifiers`' Control-dependent behavior. (`macos/Sources/Ghostty/NSEvent+Extension.swift`, lines 4-47; `Ghostty.Input.swift`, lines 67-94.)
- `ghosttyCharacters` detects a single C0 value in `event.characters` and asks AppKit for characters with Control removed. Thus a U+0003 event becomes logical text `"c"`; Ghostty core, not AppKit, owns the Ctrl-to-C0 mapping. It also removes private-use function-key characters. (`NSEvent+Extension.swift`, lines 49-75.)
- The public C event carries all seven relevant fields: action, modifiers, consumed modifiers, native keycode, text, unshifted codepoint, and composing. (`include/ghostty.h`, lines 391-399, `ghostty_input_key_s`.)

## 2. `keyDown` and text input / IME behavior

`SurfaceView.keyDown` is intentionally more than a C API call:

1. It asks core for **translation modifiers** (not event modifiers) so settings such as `macos-option-as-alt` affect character translation but not the modifiers later sent to core. It preserves hidden AppKit modifier bits and reuses the original `NSEvent` when no translation is needed because constructing an equivalent event breaks Korean input. (`SurfaceView_AppKit.swift`, lines 1101-1151; `src/apprt/embedded.zig`, lines 2011-2027.) Control-C normally reuses the original event.
2. It opens a `keyTextAccumulator`, snapshots marked-text and keyboard-layout state, clears stale redispatch state, then calls `interpretKeyEvents([translationEvent])`. (`SurfaceView_AppKit.swift`, lines 1153-1185.)
3. `insertText` clears preedit. During `keyDown` it appends committed IME text to the accumulator; outside `keyDown` it creates a modifier-free committed-text key event instead of treating text as a paste. (`SurfaceView_AppKit.swift`, lines 2070-2114, symbol `insertText`.)
4. After interpretation, `keyDown` synchronizes preedit and distinguishes in-progress composition from committed IME text. It suppresses a single C0 control value while composing, specifically so inputs such as Control-H affect the IME rather than leak to the terminal. Without accumulated committed text it calls `keyAction` with `translationEvent.ghosttyCharacters`; with committed text it submits that text as the event payload. (`SurfaceView_AppKit.swift`, lines 1187-1270 and 2149-2163.)
5. `keyAction` overlays `composing` and a safely scoped C string, then calls `ghostty_surface_key`. (`SurfaceView_AppKit.swift`, lines 1474-1495.)

For ordinary Control-C with no active composition, the expected path is therefore `keyDown → interpretKeyEvents → no committed IME payload → ghosttyCharacters == "c" → keyAction`. If an input method owns an active preedit and produces a C0 value, Ghostty suppresses it instead of interrupting the terminal. Any integration that directly manufactures `0x03` text before this logic changes IME semantics.

## 3. Binding preflight and the meaning of `consumed` / `performable`

`performKeyEquivalent` asks `surface.keyIsBinding` using a full Ghostty event whose temporary `text` points to `event.characters`. (`SurfaceView_AppKit.swift`, lines 1320-1327; `macos/Sources/Ghostty/Ghostty.Surface.swift`, lines 86-103.) The C API maps native keycode to a physical Ghostty key and calls `Surface.keyEventIsBinding`. (`src/apprt/embedded.zig`, lines 102-139 and 2046-2068.)

The flags are independent bits:

- **`consumed` defaults true**: after performing the binding, do not encode the triggering key.
- **`performable`**: consume only if the action can currently perform; if not, behave as though no binding exists.
- `all` and `global` imply core consumption; the four-bit definitions and defaults are in `src/input/Binding.zig`, lines 30-72 (`Binding.Flags`). User-facing semantics, including why performable shortcuts are not shown in menus, are documented in `src/config/Config.zig`, lines 1740-1802 (`keybind` option documentation).

There is a subtle but crucial split between **preflight** and **execution**:

- `Surface.keyEventIsBinding` returns a matching binding's flags but explicitly does **not** test whether a performable action can currently perform. (`src/Surface.zig`, lines 2610-2658.)
- In actual execution, `maybeHandleBinding` performs the action, treats `global`/`all` as consumed, and if a `performable` action returned false, returns `null` so encoding proceeds as if no binding existed. A consumed successful binding records its hash so its key release is also suppressed. (`src/Surface.zig`, lines 2963-3090, especially 3027-3079.)

The macOS frontend only routes a matching binding through a menu when there is no active sequence/table, it is not `all`, it is **not `performable`**, and it **is `consumed`**. Otherwise it calls its own `keyDown` directly. This avoids menus' unconditional consumption of an unperformable/unconsumed binding. (`SurfaceView_AppKit.swift`, lines 1329-1348.) Menu dispatch itself checks physical shortcuts before Unicode shortcuts, refreshes validation, and only performs enabled menu items. (`macos/Sources/Ghostty/Ghostty.MenuShortcutManager.swift`, lines 35-76.)

### Control-C versus Command-C under defaults

**Control-C**

- Ghostty has no default Control-C binding; the defaults explicitly reserve Control-C for process interruption and use Command on Darwin. (`src/config/Config.zig`, lines 6629-6650.)
- First `performKeyEquivalent` preflight returns no binding. Ghostty records the event timestamp and returns `false`, allowing AppKit's text-input route. If AppKit turns it into `doCommand` before `keyDown`, Ghostty redispatches it; otherwise normal first-responder `keyDown` handles it. (`SurfaceView_AppKit.swift`, lines 1276-1302, 1382-1408, 2116-2127.)
- A host framework could theoretically consume it in the interval after `false` and before Ghostty receives `keyDown`. In this incident, however, automated end-to-end tests proved that Fission delivered Control-C through Ghostty; runtime PTY inspection located the failure in a stale execution daemon. No embedding interception is required.

**Command-C**

- Darwin defaults bind Unicode `c` + `super` to `copy_to_clipboard` with `performable = true`. (`src/config/Config.zig`, lines 6629-6641.)
- Preflight reports a binding even if no selection exists. Because it is performable, the frontend deliberately skips menu dispatch and calls `keyDown` directly. Core tries the copy action; it returns true only with a selection and false otherwise. (`SurfaceView_AppKit.swift`, lines 1329-1348; `src/Surface.zig`, lines 5012-5041.)
- On success, the default consumed flag prevents terminal encoding. On failure, performable semantics allow encoding to continue, but the macOS legacy encoder explicitly emits nothing for any Command/`super`-modified key. (`src/Surface.zig`, lines 3027-3079; `src/input/key_encode.zig`, lines 529-547.) Therefore Command-C copies when possible and otherwise does nothing; it does not become `c` or `0x03` in the PTY.

## 4. Core encoding and PTY write

At the C boundary, `ghostty_surface_key` converts the external event and calls `App.keyEvent`; native keycode is mapped through `input.keycodes.entries` to the physical key before `Surface.keyCallback`. (`src/apprt/embedded.zig`, lines 102-139, 2029-2044; lines 202-230.)

`Surface.keyCallback` has this order:

1. Apply modifier remaps.
2. Resolve bindings first, including release suppression for a consumed press.
3. Respect keyboard-disabled mode and update UI/input state.
4. Call `encodeKey`; if bytes were produced, queue a small/stable/allocated write request to the IO mailbox. (`src/Surface.zig`, lines 2660-2860.)

`encodeKey` derives options from current terminal modes and invokes the key encoder, copying resulting bytes into an IO write request. (`src/Surface.zig`, lines 3184-3285.) The encoder selects Kitty protocol when enabled, otherwise legacy encoding. (`src/input/key_encode.zig`, lines 74-101.) Thus **`0x03` is the ordinary legacy result**; an application that enabled Kitty keyboard reporting may legitimately receive a protocol sequence instead, depending on negotiated flags.

In legacy mode, `ctrlSeq` is checked before generic UTF-8 output. It requires Control, strips non-binding/side/lock information and Alt, and chooses a single-byte character from logical UTF-8 or the physical logical key fallback. (`src/input/key_encode.zig`, lines 326-407 and 676-732.) For `"c"` plus Control, the mapping is explicit: `'c' => 3`. (`src/input/key_encode.zig`, lines 733-827.) The source includes direct tests for legacy Control-C producing `"\x03"`, standard/right-Control `ctrlSeq`, and non-Latin physical-C fallback. (`src/input/key_encode.zig`, lines 2133-2142 and 2547-2602.)

The final write path is:

- `Surface.queueIo` rejects write messages only in surface readonly mode, then queues to `Termio`. (`src/Surface.zig`, lines 860-894.)
- The IO thread handles `write_small`, `write_stable`, and `write_alloc` with `io.queueWrite`. (`src/termio/Thread.zig`, lines 345-368.)
- `Exec.queueWrite` copies/chunks bytes and queues an async write on the process's write stream; on Unix the PTY master is both read and write endpoint. (`src/termio/Exec.zig`, lines 403-478 and 1088-1092.)

At this point Ghostty has delivered input to the PTY. Apple's XNU source defines the default interrupt character as `CINTR = CTRL('c')` and includes `ISIG` in `TTYDEF_LFLAG`; the tty input path tests `cc[VINTR]` under `ISIG` and calls `tty_pgsignal_locked(..., SIGINT, ...)` for the terminal's process group. [Apple XNU, `bsd/sys/ttydefaults.h`, symbols `CINTR`, `TTYDEF_LFLAG`, `ttydefchars`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/ttydefaults.h); [Apple XNU, `bsd/kern/tty.c`, `ttyinput` signal branch](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c). Apple's termios manual additionally describes `tcgetattr`/`tcsetattr` and `cfmakeraw` as controlling terminal state and the raw I/O path. [Apple, `tcsetattr(3)` Mac OS X manual page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/tcgetattr.3.html) This is why “the process did not die” is not by itself proof that Ghostty failed to write Control-C: the foreground process may handle/ignore `SIGINT`, or terminal mode may expose the byte as input.

## 5. Ranked likely integration mistakes

### 1. Returning `false` from an embedding `performKeyEquivalent` and assuming Ghostty must later receive `keyDown`

**Likelihood: highest when Ghostty is hosted under SwiftUI or another command layer.** AppKit is allowed to offer the event to menus/text commands between these points. Ghostty's own `doCommand` redispatch workaround only runs if Ghostty remains the text-input client receiving that callback; an outer host can consume first.

**Probe:** log one immutable event identity tuple `(timestamp, eventNumber, type, keyCode, relevant modifiers)` at the embedding override, inherited `keyDown`, inherited `doCommand`, and PTY observer. A failing case will show Control-C at `performKeyEquivalent` but not at `keyDown`.

**Fix:** when the actual terminal view is first responder and the event is exactly bare Control-C, call the inherited Ghostty `keyDown(with: event)` once and return `true`. Fission commit `dbe17a1` implements this shape in `Apps/Desktop/Sources/Terminal/TerminalInput.swift` (committed lines 67-78 and 101-120); the research-time working tree contains a concurrent/pre-existing reversal of that production change. Preserve all non-shortcut modifier/device bits by forwarding the original event.

### 2. Sending `event.characters` (`U+0003`) as Ghostty `text`, or using the text/paste API

Ghostty expects to normalize a single C0 character back to `"c"` and encode Control itself. Supplying `text = "\x03"` with Control bypasses that contract and can select CSI-u/fixterms behavior rather than the legacy Ctrl-C branch; `ghostty_surface_text` is explicitly a paste path, subject to paste/newline/bracketed-paste processing. (`NSEvent+Extension.swift`, lines 49-75; `src/apprt/embedded.zig`, lines 2070-2080; `src/input/key_encode.zig`, lines 382-407, 479-527.)

**Probe:** Ghostty's inspector should show physical C, `Mods: Ctrl`, logical text `c`, unshifted U+0063, and PTY `03` in legacy mode—not logical text `03` as the integration's manufactured payload.

**Fix:** forward the original `NSEvent` through Ghostty's macOS `keyDown`, or faithfully reproduce every `ghosttyKeyEvent`/`ghosttyCharacters` field if using the lower-level C API.

### 3. Calling `keyDown` and then returning `false`/calling `super.performKeyEquivalent`

This permits a second AppKit route and can encode twice, execute a binding twice, or leave Ghostty's timestamp redispatch state inconsistent.

**Probe:** count calls and PTY bytes per physical event timestamp; one physical press must produce one press path and, in legacy mode, one `03` byte.

**Fix:** after direct handling, return `true` and do not call `super`. For all nonmatching events, defer to `super` unchanged.

### 4. Matching the shortcut too broadly or from the wrong field

Matching `characters == "\x03"` is input-source fragile; matching only keycode `0x08` can hijack a non-C character on another layout; ignoring Shift/Option/Command can steal distinct combinations. Conversely, comparing the whole modifier bitset to `.control` fails when caps-lock or device-dependent bits are present.

**Probe:** exercise Control-C, Control-Shift-C, Control-Option-C, Command-C, CapsLock+Control-C, right Control-C, and a non-US layout. Record `characters`, `charactersIgnoringModifiers`, `characters(byApplyingModifiers: [])`, keycode, and only the four shortcut modifiers.

**Fix:** for the narrow host workaround, require `.keyDown`, require the intersection of `[command, shift, option, control]` to equal Control, and match normalized `charactersIgnoringModifiers == "c"`; then forward the original event so Ghostty still has keycode and device flags. This is the strategy in Fission commit `dbe17a1` (`TerminalInput.swift`, committed lines 67-78), although the research-time working tree reverses it.

### 5. Rebuilding an `NSEvent` unnecessarily

Ghostty explicitly warns that an apparently equivalent reconstructed event breaks Korean input because AppKit appears to depend on event object identity/hidden state. (`SurfaceView_AppKit.swift`, lines 1118-1151.)

**Probe:** compare behavior under US, Korean 2-Set, Japanese, and a dead-key input source while preedit is active.

**Fix:** pass the original event whenever modifiers do not require translation. If reconstruction is unavoidable, copy type, location, flags, timestamp, window number, characters, characters-ignoring-modifiers, repeat, and keycode—but recognize that this still may not preserve private AppKit state.

### 6. Bypassing `interpretKeyEvents` / composition handling

Direct C submission loses marked-text synchronization, committed text accumulation, keyboard-layout-change suppression, and composing-C0 suppression. A Control key used to cancel/edit an IME preedit could incorrectly interrupt the shell.

**Probe:** begin Japanese/Korean composition, press Control-C and Control-H, then inspect preedit, committed text, and PTY bytes. No composing C0 should leak through the ordinary Ghostty path (`SurfaceView_AppKit.swift`, lines 1187-1270, 2149-2163).

**Fix:** invoke the terminal view's inherited `keyDown`, not only `surface.sendKeyEvent`, for physical AppKit events.

### 7. Losing modifiers, consumed modifiers, unshifted codepoint, or physical keycode

A “minimal” event such as `{ text: "c" }` emits plain `c`; `{ ctrl, text: nil, keycode: 0 }` may have nothing reliable to map; incorrect `consumed_mods` changes effective modifiers and binding matching. Non-Latin layouts rely on the physical/logical fallback to retain conventional Control-C behavior. (`src/input/key.zig`, lines 16-65; `src/input/key_encode.zig`, lines 705-730.)

**Probe:** inspect the complete `ghostty_input_key_s` at the C boundary. For standard Control-C expect action press, keycode 8, text `c`, composing false, mods ctrl, consumed mods empty, unshifted U+0063.

**Fix:** use Ghostty's provided `NSEvent.ghosttyKeyEvent` and `ghosttyCharacters` behavior rather than a reduced host event model.

### 8. Sending both PTY `0x03` and an explicit `SIGINT`

These are not equivalent. The PTY line discipline applies foreground-process-group and termios semantics; a direct signal chooses a PID/process group externally and duplicates interruption when `ISIG` is active.

**Probe:** run one child in canonical mode and one in raw mode while tracing bytes and signals. The terminal should write once in both cases; only the line discipline decides whether that becomes `SIGINT`.

**Fix:** send the key through Ghostty only. Never add `Process.interrupt()`, `kill`, or `tcsetpgrp` logic for keyboard Control-C.

### 9. Mistaking “no process exit” for missing routing

The child may trap/ignore `SIGINT`; a full-screen app may use raw mode and read `0x03`; Kitty keyboard protocol may encode a negotiated sequence; Ghostty readonly mode drops write requests. (`src/Surface.zig`, lines 860-894; `src/input/key_encode.zig`, lines 74-116.)

**Probe:** first prove the PTY byte with `od -An -tx1` under an appropriate raw/no-signal setup, then independently test normal shell interruption and inspect `stty -a` (`intr`, `isig`).

**Fix:** diagnose each layer separately rather than changing key routing based solely on child behavior.

## 6. Concrete end-to-end probe plan

1. **AppKit entrance:** in a debug-only subclass, log `type`, `timestamp`, `eventNumber`, `keyCode`, `modifierFlags.rawValue`, `characters` as Unicode scalar hex, `charactersIgnoringModifiers`, and `characters(byApplyingModifiers: [])` in `performKeyEquivalent`, `keyDown`, and `doCommand`.
2. **Ghostty event:** enable Ghostty's terminal inspector. Its key-event record copies the core event and the encoded PTY bytes before the mailbox can release them (`src/Surface.zig`, lines 2680-2709 and 3250-3274). Expected ordinary Control-C: physical `key_c`, Ctrl, UTF-8 `c`, PTY `03`.
3. **Binding variants:** test no custom binding, `ctrl+c=ignore`, `unconsumed:ctrl+c=reload_config`, and a performable binding. Confirm binding action-before-encoding and release suppression per `maybeHandleBinding`.
4. **PTY bytes:** run a tiny child that disables `ISIG` while retaining byte reads (or use a controlled `stty -isig` session) and print input bytes. One press should show one `03` in legacy mode.
5. **Signal behavior:** restore normal `stty sane`, run `sleep 30`, press Control-C, and verify interruption. If the byte probe passes but `sleep` does not stop, inspect foreground process group and termios rather than AppKit.
6. **Negative matrix:** verify Command-C with/without selection, Control-Shift-C, Command-Shift-C, right Control-C, CapsLock+Control-C, key repeat, inactive terminal, active search/command-palette first responder, non-US layout, and active IME preedit.
7. **Duplicate guard:** correlate every physical timestamp with exactly one Ghostty press and at most one PTY encoding. Key release is a separate event and legacy encoding intentionally emits no release bytes.

## 7. Fission runtime diagnosis and fix

Fission commit `dbe17a1` added a `FissionTerminalView.performKeyEquivalent` path that directly routed bare Control-C into inherited `keyDown`. Its event construction was compatible with Ghostty's invariants, but it was based on the wrong diagnosis. Both the shell-input and real-Pi XCUITests passed through the ordinary input path, while the user's already-running installed app remained broken.

The differentiating state was the persistent execution helper:

- Fission embeds Ghostty as an in-memory terminal backend; `FissionExecution`, not Ghostty, creates and owns each PTY.
- The running daemon started before commit `bbd3b0e`, which added controlling-terminal and foreground-process-group setup.
- The app and helper executable were upgraded later, but clients continued connecting to the daemon through the unchanged version-1 socket.
- Runtime foreground-process-group queries against that daemon's PTYs failed with `ENOTTY`, matching the symptom: Ghostty wrote Control-C, but the kernel had no valid foreground terminal process group to signal.

`TerminalExecutionProtocol.version` participates in the daemon's socket path. Bumping it from 1 to 2 forces upgraded clients onto a new socket and therefore a helper containing the corrected PTY setup. The special Control-C branch and its predicate test were removed, restoring the package's normal `performKeyEquivalent → keyDown → ghostty_surface_key` behavior.

Validation after this change:

- all 39 Desktop unit tests passed;
- all 7 Desktop UI tests passed, including clearing pending shell input and interrupting a foreground process;
- SwiftLint reported zero violations;
- `git diff --check` passed.

This incident demonstrates why the probe order in section 6 matters: successful key encoding does not prove signal delivery. After proving the key path, inspect `tcgetpgrp`, controlling-terminal ownership, `ISIG`, and the foreground process group before adding an AppKit workaround.

## Source index

Primary Ghostty symbols and line ranges used above:

- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`: `keyDown` 1101-1270; `lastPerformKeyEvent` / `performKeyEquivalent` 1276-1425; `keyAction` 1475-1495; `insertText` 2070-2114; `doCommand` 2116-2127; composing-control suppression 2149-2163.
- `macos/Sources/Ghostty/NSEvent+Extension.swift`: `ghosttyKeyEvent` 4-47; `ghosttyCharacters` 49-75.
- `macos/Sources/Ghostty/Ghostty.Input.swift`: modifier conversion 67-94; binding flag bridge 123-149; macOS physical-key mapping in `Input.Key.keyCode` 1043-1123 (C at 1081).
- `macos/Sources/Ghostty/Ghostty.MenuShortcutManager.swift`: menu shortcut dispatch 35-76; physical/Unicode normalized identities 88-166.
- `include/ghostty.h`: `ghostty_input_key_s` 391-399; surface keyboard API 1190-1197.
- `src/apprt/embedded.zig`: external-to-core event mapping 102-139; app/surface event dispatch 202-230; translation modifiers and C exports 2011-2068.
- `src/input/key.zig`: core `KeyEvent` fields and effective modifiers 8-74.
- `src/input/Binding.zig`: `Flags` 30-72.
- `src/config/Config.zig`: keybind prefix semantics 1740-1802; default copy/paste bindings 6593-6650.
- `src/Surface.zig`: readonly IO gate 860-894; binding preflight 2610-2658; callback pipeline 2660-2860; binding execution 2862-3090; key encoding/write request 3184-3285; copy performability 5012-5041.
- `src/input/key_encode.zig`: protocol selection 74-116; legacy pipeline 326-547; Ctrl/C0 mapping 676-827; Control-C tests 2133-2142 and 2547-2602.
- `src/termio/Thread.zig`: mailbox write handling 345-368.
- `src/termio/Exec.zig`: async PTY write 403-478; Unix PTY master endpoint 1088-1092.

Official Apple references:

- [Apple, *Cocoa Event Handling Guide: Handling Key Events*](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingKeyEvents/HandlingKeyEvents.html)
- [Apple XNU, `bsd/sys/ttydefaults.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/ttydefaults.h) and [`bsd/kern/tty.c`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty.c)
- [Apple, `tcsetattr(3)` Mac OS X manual page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/tcgetattr.3.html)

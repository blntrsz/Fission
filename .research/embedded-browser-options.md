# Embedded browser options for Fission

**Status:** recommendation research
**Current as of / sources accessed:** 2026-09-03
**Scope:** a browser surface rendered inside the native macOS 14+ Fission window. This is not a recommendation to automate or launch an installed browser.

## Executive recommendation

**Build the MVP with Apple's `WKWebView`.** It is the only option that is simultaneously a first-class AppKit view, directly callable from Swift, already present on every supported Mac, security-updated by Apple, accessible through the native macOS accessibility stack, and straightforward to ship in Fission's existing hardened-runtime DMG. `WKWebView` is an `NSView` on macOS and Apple explicitly supports embedding it in an app UI; it provides navigation/UI delegates and an immutable-at-creation configuration ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [WebKit for AppKit and UIKit](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)).

For Fission specifically:

- Add a browser-tab model alongside `TerminalTab`, not inside the terminal module. Host `WKWebView` through `NSViewRepresentable`, analogous in shape to the existing embedded Ghostty surface but with a feature-owned coordinator/delegates. Apple defines `NSViewRepresentable` specifically for creating and updating an AppKit view from SwiftUI ([NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)).
- Give each **Thread** a persistent `WKWebsiteDataStore(forIdentifier: thread.id)` and let browser tabs in that Thread share it. That initializer is available from macOS 14 and creates/returns a persistent store for a UUID; Apple also provides removal by identifier ([persistent store initializer](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init%28foridentifier%3A%29), [store removal](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove%28foridentifier%3Acompletionhandler%3A%29)). This maps cleanly to Fission's durable Thread concept while preventing cookies/site data from leaking between Threads. Offer a nonpersistent store for an explicit private tab/session ([WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)).
- Treat the MVP as an **in-app research/documentation browser**, not a promise of Chrome identity or perfect Chrome-site compatibility. WebKit has current web-platform support, but it is not Chromium, and its tracking protections block third-party cookies by default ([WebKit tracking prevention](https://webkit.org/tracking-prevention/)). Test the actual product-critical sites rather than inferring compatibility from generic benchmarks.
- Keep the page-to-native bridge absent or allowlisted initially. If needed later, use `WKContentWorld` and narrowly scoped script-message handlers rather than exposing a general privileged object to arbitrary pages ([WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld), [WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)).

**Only consider CEF as a later upgrade if measured, important Chromium-only failures remain after a WKWebView proof-of-concept.** CEF is a real native embedder and offers stronger control and deterministic Chromium behavior, but it introduces a C/C++ or Objective-C++ boundary, a large per-architecture runtime, multiple helper apps/processes, custom signing/notarization work, and an ongoing rapid browser-update obligation. Official CEF guidance recommends release branches for production and notes that CEF updates are manually integrated and may lag Chromium announcements ([CEF branches and building](https://chromiumembedded.github.io/cef/branches_and_building.html)).

**Do not choose Electron, Qt WebEngine, Ultralight, Servo, or Gecko for the current requirement.** Qt WebEngine is technically embeddable but adds almost all of CEF's Chromium weight plus Qt integration and licensing complexity. Electron's supported web surface belongs inside an Electron-owned `BaseWindow`, not an arbitrary SwiftUI/AppKit view. Ultralight is not a full modern-browser substitute and currently lacks platform accessibility hooks. Servo's embedding API remains incomplete. GeckoView is Android-only; Mozilla publishes no supported desktop Gecko embedding SDK.

## Compact decision matrix

Ratings are relative to this repository and requirement, not general engine quality.

| Option | Actually embeds in native Swift macOS UI? | Web compatibility | Integration / distribution cost | Session isolation | Accessibility | License / update burden | Decision |
|---|---|---:|---:|---:|---:|---:|---|
| **WKWebView / system WebKit** | **Yes:** native `NSView`; direct Swift API | High, Safari/WebKit; not Chrome-identical | **Lowest:** no bundled engine/helpers | Persistent per-Thread stores and ephemeral stores; process placement is WebKit-managed | Native `NSAccessibility` conformance | OS framework; Apple supplies WebKit security updates | **Use for MVP** |
| **CEF** | **Yes:** native windowed or off-screen Chromium, but bridge C/C++ to Swift | **Highest for Chromium-targeted sites** | **Very high:** framework, helpers, resources, signing, universal packaging | Separate request contexts isolate storage and are never co-hosted in one renderer | Likely good in windowed mode; OSR needs custom accessibility work; validate | BSD; Fission must track and ship updates | **Conditional later upgrade** |
| **Qt WebEngine** | Technically yes through Qt/C++ and macOS native-handle interop | Chromium-class | Very high: Qt runtime + `QtWebEngineProcess` + Chromium resources | Profiles support storage separation | Qt/Chromium support, but bridge must be validated | LGPLv3/GPL/commercial + Chromium notices; app-store restriction | **No** |
| **Electron host process** | **No supported child-`NSView` API** for an existing Swift app; Electron owns the window | Chromium-class | Very high and architectural rewrite/unsupported window composition | Electron sessions/partitions | Chromium accessibility | MIT, but Fission ships Electron/Chromium updates | **No for embedding; only if app shell is rewritten** |
| **Ultralight** | Possible only through C/C++ low-level rendering/custom host work; no documented drop-in `NSView` | Inadequate evidence for arbitrary modern sites; feature gaps | High custom rendering/input/platform work | Must design in host | **No OS accessibility hooks documented** | Proprietary core; paid thresholds; host owns update risk | **No** |
| **Servo** | Experimental custom integration possible; no mature Swift/AppKit webview | Developing; not a Chrome/Safari compatibility target | Very high Rust/graphics/media/productization work | Immature embedding surface | Servo has accessibility work, but embedder readiness unproven | MPL-2.0; app owns engine updates | **No now; watch** |
| **Gecko / GeckoView** | **No supported macOS embedding SDK**; GeckoView is Android `View` | Firefox-class in Firefox/Android | Effectively a Firefox fork/productization effort | N/A for supported macOS embedding | N/A | MPL ecosystem and self-maintained fork | **No** |
| **Wry/Tauri or `webview/webview`** | Possible, but on macOS these wrap WKWebView | Same as WKWebView | Extra Rust/C++ abstraction with less direct API access | Ultimately WKWebView stores | Ultimately WKWebView | MIT/Apache wrappers + OS engine | **No benefit for this Swift-only app** |
| **Installed Safari/Chrome via automation/CDP** | **No:** controls a separate browser process/window | Browser-dependent | Does not satisfy requirement | Browser-profile-dependent | Browser-owned | Browser-owned | **Eliminate** |

## Detailed option notes

### 1. Apple WKWebView / system WebKit — recommended

#### Fit with Fission

Fission's desktop target is SwiftUI/AppKit, deploys to macOS 14.0, enables hardened runtime, and already keeps long-lived tab surface objects alive while switching visibility (`Apps/Desktop/Sources/Terminal/TerminalWorkspaceView.swift`; `Apps/Desktop/FissionDesktop.xcodeproj/project.pbxproj`). `WKWebView` fits that pattern directly: create one long-lived view per browser tab, retain it while hidden so page/session state survives switching, and expose observable navigation state through a feature-owned view model/coordinator.

No engine binary is added to the app. WebKit is a system framework, while web content is rendered outside the application process for security and stability ([WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool)). **Inference:** this should add negligible packaged size relative to CEF/Qt/Electron, though caches and website data will still consume runtime disk space.

#### Compatibility and lifecycle

`WKWebView` uses the same WebKit family as Safari, but it is not Safari's browser UI and does not inherit Safari extensions, profiles, toolbar, or an installed Safari session merely because Safari is present. The API creates a web view owned by Fission ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)). WebKit fixes and features are delivered by Apple; Apple's current Safari security releases explicitly contain WebKit fixes, including memory-safety and sandbox issues ([Apple Safari security releases](https://support.apple.com/en-us/100100), example [Safari 26.6.1 security content](https://support.apple.com/en-us/148286)).

Compatibility risks are specific and testable:

- Chromium-only APIs, Chrome extensions, enterprise Chrome policies, and Chrome-profile state are not available.
- WebKit's full third-party-cookie blocking and storage partitioning can affect embedded authentication/widgets ([tracking prevention](https://webkit.org/tracking-prevention/), [Storage Access API update](https://webkit.org/blog/11545/updates-to-the-storage-access-api/)).
- WebKit behavior depends on the user's installed macOS/Safari updates rather than a runtime version pinned by Fission. This removes Fission's engine-patching duty but means two supported Macs may temporarily differ. WebKit documents feature delivery in Safari releases, including WKWebView API additions ([WebKit Safari release notes](https://webkit.org/blog/16301/webkit-features-in-safari-18-2/)).

#### API coverage

WKWebView covers the expected MVP and most likely follow-ons:

- **Navigation/history/progress/title:** `load`, `goBack`, `goForward`, `reload`, `stopLoading`, `url`, `title`, `estimatedProgress`, and `WKNavigationDelegate` policy/lifecycle callbacks ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview), [WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate)).
- **Cookies/site data:** persistent, nonpersistent, and macOS 14 UUID-addressed profile stores; cookie enumeration/set/delete through `WKHTTPCookieStore` ([WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)).
- **Downloads:** `WKDownload` and delegate callbacks for destination, redirects, authentication, completion, and failure ([WKDownload](https://developer.apple.com/documentation/webkit/wkdownload), [WKDownloadDelegate](https://developer.apple.com/documentation/webkit/wkdownloaddelegate)). Fission must provide destination UX and security-scoped/file access behavior appropriate to its sandbox choice.
- **Uploads:** on macOS, file inputs use `WKUIDelegate.webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)`; Apple notes uploads are disabled if the delegate method is absent ([open-panel delegate](https://developer.apple.com/documentation/webkit/wkuidelegate/webview%28_%3Arunopenpanelwith%3Ainitiatedbyframe%3Acompletionhandler%3A%29)).
- **JavaScript bridge:** asynchronous script evaluation, injected scripts, and named message handlers; isolated `WKContentWorld`s reduce collisions with page JavaScript ([WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller), [WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld)). A bridge is powerful and therefore should be origin-gated and minimal.
- **Custom schemes:** register a `WKURLSchemeHandler` on the configuration and service its `WKURLSchemeTask`s ([WKURLSchemeHandler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)).
- **Permissions and webpage UI:** `WKUIDelegate` handles new windows/JavaScript dialogs and media-capture permission; the media callback identifies security origin, frame, and camera/microphone type ([WKUIDelegate](https://developer.apple.com/documentation/webkit/wkuidelegate), [media permission delegate](https://developer.apple.com/documentation/webkit/wkuidelegate/webview%28_%3Arequestmediacapturepermissionfor%3Ainitiatedbyframe%3Atype%3Adecisionhandler%3A%29)). macOS privacy usage descriptions/entitlements remain required where applicable ([Hardened Runtime configuration](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)).
- **Content blocking:** compile JSON rule lists with `WKContentRuleListStore` and attach them through `WKUserContentController` ([WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)). This is suitable for tracker/ad rules, not an arbitrary synchronous network interceptor.
- **Inspection:** `isInspectable` permits Safari Web Inspector on inspectable views ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)). Keep it enabled in development and make any release exposure an explicit product decision.
- **Authentication/navigation policy:** navigation delegates can allow/cancel actions/responses and handle URL authentication challenges ([WKNavigationDelegate](https://developer.apple.com/documentation/webkit/wknavigationdelegate)).

Potential limitation: arbitrary browser-wide request interception/rewriting is not a general WKWebView API. Apple's Developer Technical Support explains that networking runs in a separate WebKit process and recommends supported mechanisms such as a custom/local proxy where interception is genuinely required ([Apple DTS forum guidance](https://developer.apple.com/forums/thread/780031)). Do not plan on `URLProtocol` swizzling for normal HTTPS traffic.

#### Isolation, sandbox, signing, accessibility

Use one UUID-backed `WKWebsiteDataStore` per Thread and share it across that Thread's tabs. This gives separate cookies, caches, and site data. Use `nonPersistent()` for private tabs. Do **not** promise one OS process per Thread/tab: deprecated `WKProcessPool` controls no longer provide process-placement guarantees ([WKProcessPool](https://developer.apple.com/documentation/webkit/wkprocesspool)). Data separation is the supported product guarantee; renderer-process allocation remains WebKit-managed.

`WKWebView` conforms to macOS accessibility protocols, including `NSAccessibilityProtocol`/`NSAccessibilityElementProtocol` ([WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)). The POC must still test Fission's surrounding tab controls, focus transfer, VoiceOver navigation, and hidden-tab accessibility state.

A WKWebView app can be Developer-ID signed, notarized, and shipped in the current normal DMG. Fission already enables hardened runtime and has a DMG task. Apple requires Developer ID signing, hardened runtime, notarization, and recommends stapling for direct distribution ([notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)). WKWebView adds no nested engine code to sign. App Sandbox is separate from hardened runtime; if Fission later enables App Sandbox, network client and user-selected-file capabilities must be configured ([App Sandbox entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox)).

**Important browser-entitlement caveat:** Apple's managed default-browser entitlement grants capabilities such as unrestricted-domain full-script access and Service Workers ([preparing a default browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)). Fission should not assume it qualifies or needs this entitlement. Validate required sites, especially service-worker-heavy apps, under Fission's ordinary entitlement set.

### 2. Chromium Embedded Framework (CEF) — credible but expensive fallback

CEF is expressly a BSD-licensed framework for embedding Chromium-based browsers in other applications, with stable C and C++ APIs ([CEF README](https://github.com/chromiumembedded/cef/blob/master/README.md), [CEF license](https://github.com/chromiumembedded/cef/blob/master/LICENSE.txt)). It supports macOS ARM64 and x86_64 distributions and sample native applications ([cef-project](https://github.com/chromiumembedded/cef-project/blob/master/README.md)). macOS 14 is within current CEF's deployment range; current generated build configuration targets macOS 12 and documents current Xcode/macOS build prerequisites ([CEF CMake template](https://github.com/chromiumembedded/cef/blob/master/CMakeLists.txt.in)).

#### Integration architecture

There is no official Swift package or Swift API. Fission would need an Objective-C++/C++ adapter that presents a small Swift-facing interface, owns CEF lifecycle/thread dispatch, and exposes a native child view. That is an inference from CEF's official C/C++ API surface, not a documented Swift recipe ([CEF README](https://github.com/chromiumembedded/cef/blob/master/README.md)). Off-screen rendering is also possible but would make Fission responsible for texture/pixel presentation, input-method/focus details, and accessibility; prefer CEF's windowed macOS path for any POC.

CEF is multi-process. The app bundle normally includes `Chromium Embedded Framework.framework`, resources, and helper applications; CEF's generated macOS build creates GPU, renderer, plugin, alerts, and normal helper variants ([CEF macOS build variables](https://github.com/chromiumembedded/cef/blob/master/cmake/cef_variables.cmake.in), [CEF settings paths](https://github.com/chromiumembedded/cef/blob/master/include/internal/cef_types.h)). The macOS sandbox implementation requires runtime framework loading rather than direct linking ([CefScopedLibraryLoader](https://github.com/chromiumembedded/cef/blob/master/include/wrapper/cef_library_loader.h)). This “CEF/Chromium sandbox” must not be confused with Apple's App Sandbox.

Binary cost is material. The official automated-build index currently publishes separate ARM64 and x86_64 archives; as accessed 2026-09-03, recent stable/LTS minimal archives are roughly 116–120 MB **compressed per architecture**, while standard SDK archives are roughly 265–297 MB per architecture ([official CEF build index JSON](https://cef-builds.spotifycdn.com/index.json)). Those archive sizes are not final app sizes, but they establish the order of magnitude. **Inference:** a universal bundled CEF runtime will add hundreds of megabytes installed unless aggressively pruned, and building two architectures then combining/signing them complicates Fission's currently simple Xcode/DMG pipeline.

#### Capability and isolation advantages

CEF offers broader browser-embedder control than WKWebView:

- `CefBrowserHost` includes explicit downloads, DevTools UI/protocol methods, and browser creation with a request context ([CefBrowserHost](https://cef-builds.spotifycdn.com/docs/146.0/classCefBrowserHost.html)).
- `CefRequestContext` can isolate or share storage. CEF explicitly guarantees browsers with different request contexts are never hosted in the same renderer process ([CefRequestContext](https://cef-builds.spotifycdn.com/docs/125.0/classCefRequestContext.html)). This supports strong per-Thread context isolation; tabs within a Thread could share a context, or high-risk tabs could receive separate contexts.
- Cookie managers expose visit/set/delete/flush operations ([CefCookieManager](https://cef-builds.spotifycdn.com/docs/146.0/classCefCookieManager.html)).
- Client handlers cover navigation/resource requests, downloads, file dialogs, JavaScript dialogs, authentication, and permissions ([CefClient](https://cef-builds.spotifycdn.com/docs/146.0/classCefClient.html), [CefPermissionHandler](https://cef-builds.spotifycdn.com/docs/146.0/classCefPermissionHandler.html), [CefDownloadHandler](https://cef-builds.spotifycdn.com/docs/146.0/classCefDownloadHandler.html), [CefDialogHandler](https://cef-builds.spotifycdn.com/docs/146.0/classCefDialogHandler.html)). Resource handlers can cancel/redirect requests or provide custom responses, making custom schemes and programmable content blocking possible, but placing security-sensitive networking policy in Fission ([CefResourceRequestHandler](https://cef-builds.spotifycdn.com/docs/146.0/classCefResourceRequestHandler.html), [CEF scheme-handler factory](https://cef-builds.spotifycdn.com/docs/146.0/classCefSchemeHandlerFactory.html)).
- CEF supplies browser/renderer process messaging and a message-router abstraction suitable for asynchronous JavaScript/native queries ([CEF general usage](https://chromiumembedded.github.io/cef/general_usage.html), [CefMessageRouterBrowserSide](https://cef-builds.spotifycdn.com/docs/146.0/classCefMessageRouterBrowserSide.html)).
- Chromium rendering gives the strongest match for sites primarily tested against Chrome. It still does not make the embed “Google Chrome”: Chrome-branded services, an installed Chrome profile, Chrome extensions, and Chrome UI are not automatically included; CEF describes itself as Chromium-based ([CEF README](https://github.com/chromiumembedded/cef/blob/master/README.md)).

Accessibility needs a gate, not an assumption. CEF exposes accessibility-state and tree-change APIs. Its header states that windowless/OSR mode provides tree-only accessibility without native platform objects; a current open macOS issue reports a VoiceOver crash in the OSR sample ([CEF browser accessibility API](https://github.com/chromiumembedded/cef/blob/master/include/cef_browser.h), [CEF issue #3595](https://github.com/chromiumembedded/cef/issues/3595)). **Inference:** windowed CEF may inherit Chromium's normal macOS accessibility more successfully, but Fission must prove VoiceOver and keyboard behavior before adoption.

#### Distribution, security, and maintenance

A normal notarized DMG is **plausible**, but CEF does not publish a complete notarization recipe. CEF's sample builds run as `.app` bundles, yet CEF deliberately clears automatic code signing and its official tutorial stops before distribution ([CEF hands-on tutorial](https://github.com/chromiumembedded/cef/blob/master/docs/hands_on_tutorial.md), [CEF build variables](https://github.com/chromiumembedded/cef/blob/master/cmake/cef_variables.cmake.in)). Therefore “CEF can ship in Fission's notarized DMG” is an inference that must be validated by a distribution POC, not accepted as established project support.

The pipeline would have to sign every nested framework/library/helper from the inside out, with correct per-process hardened-runtime entitlements, then sign the container and notarize it. Apple explicitly says to sign nested code inside-out and not use `--deep` for signing (although `--deep --strict` is useful for verification) ([Apple distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [notarization troubleshooting](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)). Any JIT/runtime exceptions must be narrowly scoped because Apple says hardened-runtime exceptions weaken protection ([Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)).

Fission becomes responsible for monitoring, testing, and shipping CEF/Chromium security updates. CEF recommends frozen-API release branches for production, says support normally ends as Chromium leaves Stable except selected LTC/LTS branches, and notes branch updates are manual ([CEF branches](https://chromiumembedded.github.io/cef/branches_and_building.html)). This is the largest long-term cost—not the initial browser view.

### 3. Qt WebEngine — technically credible, wrong fit

Qt WebEngine embeds Chromium rather than Google Chrome and supports macOS ([Qt WebEngine overview](https://doc.qt.io/qt-6/qtwebengine-overview.html)). It has rich profiles, custom schemes, permissions, downloads, PDF, spellcheck, DevTools, WebGL/WebRTC, and other browser features ([Qt WebEngine features](https://doc.qt.io/qt-6/qtwebengine-features.html)). Current Qt documents universal x86_64/ARM64 builds for macOS ([Qt for macOS](https://doc.qt.io/qt-6/macos.html)).

It can technically be placed into a native Cocoa hierarchy: on macOS a Qt `WId` maps to `NSView *`, and Qt documents obtaining/reparenting a native handle when embedding Qt into a native application ([Qt platform integration](https://doc.qt.io/qt-6/platform-integration.html), [window embedding example](https://doc.qt.io/qt-6/qtdoc-demos-windowembedding-example.html)). This requires C++/Objective-C++ and running Qt's application/event/rendering machinery alongside SwiftUI. Native-handle interfaces have portability/lifetime caveats, and Qt documents focus, stacking, clipping, and performance limitations for embedded native windows ([QWidget window containers](https://doc.qt.io/qt-6/qwidget.html)).

Deployment requires Qt libraries/QML imports as applicable, `QtWebEngineProcess`, Chromium resources/translations/codecs, and helper-specific signing/entitlements ([Deploying Qt WebEngine](https://doc.qt.io/qt-6/qtwebengine-deploying.html)). Thus it does not reduce the CEF complexity that would motivate leaving WKWebView; it adds another UI/application framework.

Licensing is also less simple: Qt WebEngine is available commercially or under LGPLv3/GPL terms, and Chromium third-party licenses still apply ([Qt WebEngine licensing](https://doc.qt.io/qt-6/qtwebengine-licensing.html), [Qt LGPL obligations](https://www.qt.io/development/open-source-lgpl-obligations)). Qt states that Mac App Store distribution is unsupported for Qt WebEngine because of Chromium private APIs and sandbox conflicts ([Qt WebEngine platform notes](https://doc.qt.io/qt-6/qtwebengine-platform-notes.html)). A Developer-ID DMG is supported by Qt's deployment tools, including signing/notarization options ([Qt macOS deployment](https://doc.qt.io/qt-6/macos-deployment.html)). Since Fission uses a DMG today, app-store exclusion is not immediately fatal, but it unnecessarily forecloses an option.

**Decision:** no. If Chromium becomes mandatory, direct CEF provides a thinner conceptual dependency and more direct embedder control.

### 4. Electron / separate Chromium host process — not a native-view embedding solution

Electron embeds Chromium and Node.js and uses a main process plus renderer processes ([Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)). Its current supported native-like web surface, `WebContentsView`, is attached to an Electron `BaseWindow`'s `contentView`; deprecated `BrowserView` should not be used for new work ([WebContentsView](https://www.electronjs.org/docs/latest/api/web-contents-view), [BrowserView](https://www.electronjs.org/docs/latest/api/browser-view)). Electron does not document exporting that surface as an `NSView` child that an existing SwiftUI application can own.

Electron documents calling native Objective-C/Swift from an Electron app via native Node addons, including macOS-native integration; that architecture embeds native capability **into Electron**, not Electron's renderer into Fission ([Electron Swift/macOS native-code tutorial](https://www.electronjs.org/docs/latest/tutorial/native-code-and-electron-swift-macos)). A helper Electron app whose borderless window is positioned over Fission would remain another window/process tree with fragile focus, z-order, Spaces/full-screen, accessibility, and lifecycle behavior. **Inference:** it does not meet “embedded as a tab” and should be rejected unless the entire desktop shell is intentionally rewritten around Electron.

Electron can be signed/notarized and distributed on macOS ([Electron code signing](https://www.electronjs.org/docs/latest/tutorial/code-signing)), but Fission would then carry Electron's runtime, Node security boundary, helper processes, packaging toolchain, and update duty. Electron explicitly recommends using current releases for Chromium security fixes and supports only its latest three stable major lines ([Electron security](https://www.electronjs.org/docs/latest/tutorial/security)).

### 5. Ultralight — embeddable renderer, not suitable as Fission's general browser

Ultralight is a proprietary lightweight HTML renderer with macOS x64/ARM64 support; its optional AppCore uses Cocoa/Metal ([Ultralight repository](https://github.com/ultralight-ux/Ultralight), [AppCore](https://github.com/ultralight-ux/AppCore)). AppCore owns a window/loop, while an existing native host can use the lower-level renderer and supply platform/rendering integrations ([Ultralight platform API](https://ultralig.ht/api/cpp/1_4_0/classultralight_1_1_platform), [custom GPU driver](https://docs.ultralig.ht/docs/using-a-custom-gpudriver)). There is no official drop-in `NSView` browser control in the reviewed documentation. **Inference:** Fission would need a C/C++ bridge plus substantial off-screen Metal/input/clipboard/font/file-system integration.

It provides JavaScriptCore interop ([JavaScript interop](https://docs.ultralig.ht/docs/about-javascript-interop)), but this is not evidence of compatibility with arbitrary production websites. The project's feature table identifies meaningful gaps and states ARIA/platform accessibility hooks are not connected to OS accessibility services ([supported web features](https://github.com/ultralight-ux/Ultralight/wiki/Supported-Web-Features)). That alone is a no-go for a general browser tab.

The core renderer is proprietary. Official pricing currently has revenue/feature limits on free use and paid per-application plans; WebCore/AppCore have separate LGPL/BSD components ([Ultralight pricing](https://ultralig.ht/pricing), [Ultralight repository licensing summary](https://github.com/ultralight-ux/Ultralight)). The reviewed official material contains no end-to-end Developer ID/notarization recipe. **Inference:** bundled signed dylibs could likely be carried in a normal notarized app, but Fission would have to prove that pipeline and any JIT entitlements itself. **Decision:** no, unless the requirement changes from general web browsing to a controlled, app-authored HTML UI and accessibility is separately solved.

### 6. Servo — promising research project, not production-ready here

Servo explicitly aims to be an embeddable Rust engine and develops on 64-bit macOS ([Servo repository](https://github.com/servo/servo)). However, its official embedding overview says documentation is sparse and under development, and current suggested integrations are Rust/Tauri/GTK oriented rather than a packaged AppKit webview ([Servo embedding overview](https://book.servo.org/embedding/overview.html)). Its embedding roadmap remains active ([Servo embedding issue #27579](https://github.com/servo/servo/issues/27579)); a current maintainer discussion says the C API exposes only basic integration-test needs and lacks ordinary webview operations such as complete resize/scroll support ([Servo C embedding discussion](https://github.com/servo/servo/discussions/32618)).

A macOS build requires Xcode plus Rust/Homebrew tooling and GStreamer dependencies for media ([Servo macOS build](https://book.servo.org/building/macos.html), [Servo repository build instructions](https://github.com/servo/servo)). The repository is MPL-2.0 ([Servo license](https://github.com/servo/servo/blob/main/LICENSE)). Servo's current macOS release instructions warn that its nightly application is not code-signed, so there is no first-party evidence of a ready notarized embedding distribution ([Servo downloads](https://servo.org/download/)). **Decision:** watch the project, but no production POC until it publishes a stable C/Swift-callable embedding surface, a native macOS host example, and a credible security/update/distribution story.

### 7. Gecko / GeckoView — eliminate

Mozilla's supported embeddable Gecko product is GeckoView, an **Android** library whose UI class is an Android `View` and whose API revolves around Android `GeckoRuntime`/`GeckoSession` ([GeckoView architecture](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/contributor/geckoview-architecture.html), [GeckoView quick start](https://mozilla.github.io/geckoview/consumer/docs/geckoview-quick-start)). macOS appears as a host on which developers can build Android GeckoView or desktop Firefox, not as a GeckoView target ([GeckoView contributor guide](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/contributor/for-gecko-engineers.html), [building Firefox on macOS](https://firefox-source-docs.mozilla.org/setup/macos_build.html)).

Mozilla's source docs describe Gecko's internal browsing-context embedding components, but not a stable, distributable native macOS embedding SDK ([Gecko embedding internals](https://firefox-source-docs.mozilla.org/dom/navigation/embedding.html)). **Decision:** no. Using Gecko would effectively mean maintaining a Firefox-derived product/fork, not consuming a component comparable to WKWebView or CEF.

### 8. Wrappers and non-options

- **Wry/Tauri:** Wry uses WKWebView on macOS and adds a Rust abstraction, custom-protocol and IPC APIs ([Wry repository](https://github.com/tauri-apps/wry), [Tauri architecture](https://v2.tauri.app/concept/architecture/)). It is credible for a Rust/cross-platform shell but provides no engine advantage to this Swift-only macOS target. Use WebKit directly.
- **`webview/webview`:** this small C/C++ library also uses Cocoa/WebKit on macOS ([project repository](https://github.com/webview/webview)). It hides rather than expands the native API and adds a needless C++ boundary.
- **Microsoft WebView2:** it is a Windows embedding product. Microsoft's macOS support request is closed “not planned” ([WebView2 platforms](https://learn.microsoft.com/microsoft-edge/webview2/), [macOS request #1314](https://github.com/MicrosoftEdge/WebView2Feedback/issues/1314)).
- **Raw Chromium `//content`:** Chromium maintainers state that only Chrome's use of the Content API is officially supported, with no API-stability guarantee, and recommend a stable layer such as CEF for external embedders ([Chromium embedder guidance](https://groups.google.com/a/chromium.org/g/chromium-dev/c/aGWheqrFUQw)). Do not build a bespoke Chromium embedder.
- **Installed Safari:** Safari app/web extensions can add extension UI, scripts, and popovers, but do not transfer Safari's tab UI into another app. The native app should create its own WKWebView ([Safari toolbar extension UI](https://developer.apple.com/documentation/safariservices/adjusting-settings-for-a-toolbar-item), [Safari Web Extensions](https://developer.apple.com/documentation/safariservices/safari-web-extensions)).
- **Installed Chrome:** Chrome DevTools Protocol controls/debugs targets in a separately running Chrome instance over a debugging connection; its documented setup launches Chrome with a remote-debugging port/profile ([Chrome remote debugging](https://developer.chrome.com/docs/devtools/remote-debugging/local-server), [Chrome DevTools Protocol](https://developer.chrome.com/docs/devtools/protocol-monitor)). It does not provide an AppKit child view. Automation is useful for testing, not embedding.

## Suggested proof of concept

Build a **WKWebView-only spike** behind no production UI commitment. Keep all code temporary or on a spike branch; the result of this research is not a request to implement it now.

### POC shape

1. Add a browser tab type to one Thread workspace with a retained `WKWebView` hosted by `NSViewRepresentable`. Exercise switching among terminal and browser surfaces repeatedly; preserve page state and restore focus correctly.
2. Use `WKWebsiteDataStore(forIdentifier: thread.id)` for normal tabs. Open the same authenticated test site in two Threads and prove isolation; open two tabs in one Thread and prove intended sharing. Add one ephemeral-store test.
3. Implement only baseline browser chrome: URL/title, loading/progress, back/forward/reload/stop, new-window policy, external-scheme policy, TLS/auth challenge default handling, and visible load errors.
4. Exercise controlled file upload and download. Save downloads only after an explicit user destination choice. Confirm camera/microphone prompts are origin-labelled and denied by default until product policy exists.
5. Keep native messaging disabled for arbitrary origins. Separately prove an allowlisted isolated-content-world message, with payload validation and handler cleanup, if agent/browser integration is an actual requirement.
6. Enable inspection in Debug and verify Safari Web Inspector. Test a compiled content-rule list and a custom scheme only if either is in MVP scope.
7. Test on macOS 14 (minimum) and the current macOS release, Intel if still a promised shipping architecture, and Apple Silicon.
8. Package exactly as production intends: Release, Developer ID, hardened runtime, notarized and stapled DMG. Verify with `codesign --verify --deep --strict`, `spctl`, offline Gatekeeper launch, and a clean user account. Apple documents these signing/notarization expectations ([notarization troubleshooting](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)).
9. Measure installed-app delta, cold first-paint, warm navigation, memory/process count for 1/5/20 tabs, hidden-tab CPU, crash recovery, and Thread deletion's website-data cleanup.
10. Run VoiceOver/keyboard tests: address bar → page → tab strip traversal, headings/links/form controls, text selection, downloads/permission dialogs, hidden-tab exclusion, zoom, Reduce Motion/Increase Contrast, and dynamic page updates.

### Compatibility test corpus

Product owners should name the corpus before the spike. At minimum include:

- the web apps Fission users are expected to keep beside terminals (source hosting, issue tracker, docs, localhost development app);
- OAuth/OIDC login and multi-factor flows;
- third-party-cookie/storage-access dependent embeds;
- service-worker/PWA-heavy site;
- WebSocket/SSE app and localhost with a self-signed certificate (expected error behavior, not an unsafe bypass);
- file upload/download, PDF, camera/microphone if in scope;
- WebGL/canvas/video if in scope;
- enterprise proxy/VPN environment if a target customer requires it.

### WKWebView go/no-go criteria

**Go** when all are true:

- Every named must-support site completes its critical user journey on macOS 14 and current macOS; any limitation is documented and accepted.
- Per-Thread persistent storage is demonstrably isolated and removable; same-Thread sharing matches the product decision.
- No arbitrary-origin privileged JavaScript bridge exists, and navigation/new-window/custom-scheme policies fail closed.
- Uploads, downloads, permissions, auth, crashes, and load errors have coherent native UX.
- VoiceOver and full-keyboard navigation pass the agreed accessibility checklist.
- Hidden tabs do not impose unacceptable CPU/memory; tab retention/eviction behavior is defined.
- The exact release DMG signs, notarizes, staples, installs, and launches under Gatekeeper with no new broad hardened-runtime exception.

**No-go / trigger a CEF spike** when at least one must-support workflow fails because of an established WebKit engine limitation (not unfinished Fission UI), and the product value exceeds the ongoing Chromium cost. Typical triggers are indispensable Chromium-only APIs/site behavior, required low-level request interception, Chrome-target parity, or stronger request-context/process control than WebKit exposes.

### CEF upgrade gate

Do not begin production CEF work until a separate spike proves all of these:

1. A minimal Objective-C++ adapter can host **windowed** CEF inside Fission's SwiftUI hierarchy with correct resize, IME, drag/drop, menus, focus, Spaces/full-screen, sleep/wake, and tab destruction.
2. ARM64 and x86_64 artifacts can be reproducibly acquired/pinned and assembled without committing an opaque oversized binary casually to the source tree.
3. Frameworks/resources/all helper variants are signed inside-out; the hardened-runtime app is accepted by notarization and launches from a stapled DMG on a clean Mac.
4. Per-Thread `CefRequestContext`s isolate cookies/cache and renderer processes as intended.
5. VoiceOver and keyboard accessibility pass in the selected rendering mode.
6. Added compressed DMG size, installed size, memory, startup, and background-process costs have explicit product approval.
7. The team owns a written Chromium response policy: monitoring, maximum days to security update, CI smoke corpus, rollback, and release mechanism.
8. BSD/Chromium third-party notices are generated and reviewed.

Failure of signing/notarization, accessibility, or update ownership is an immediate **no-go**, even if pages render better.

## Open product questions that can change the choice

1. **What is “browser” here?** A documentation/localhost companion strongly favors WKWebView. A Chrome-compatible development browser with CDP, extension semantics, enterprise policies, or exact Chrome behavior may justify CEF.
2. **Which sites and workflows are contractual must-support targets?** The engine decision cannot be made from “modern web” in the abstract.
3. **What should share identity?** All Fission Threads, one profile per Thread, one profile per tab, or explicit named profiles? The recommendation assumes same-Thread sharing and cross-Thread isolation.
4. **Must Fission reuse Safari/Chrome login state?** Neither WKWebView nor CEF should be expected to import or live-share an installed browser profile. If that is required, privacy/security and browser-vendor support need separate research.
5. **Are private/ephemeral tabs required, and what happens to browser data when a Thread is settled or deleted?** “Settled” should not silently mean “erase credentials” without an explicit retention policy.
6. **Are agent/native automation features required?** Define exact operations. Page reading, screenshots, script execution, request interception, DOM automation, CDP, and extension support have very different security and engine implications.
7. **Will arbitrary Internet pages receive a native bridge?** If yes, define an origin/capability permission model before implementation.
8. **Are downloads/uploads, camera, microphone, location, notifications, passkeys/WebAuthn, DRM video, PDF, printing, WebGL/WebGPU, and service workers MVP requirements?** Each needs explicit POC coverage and some need app entitlements/usage descriptions.
9. **Must content blocking be Safari-rule-list compatible, extension compatible, or a fully programmable request filter?** WK content rules satisfy only the first class.
10. **Is Intel support required?** Bundled Chromium's binary/distribution penalty grows substantially for a universal app; WKWebView's app-size impact does not.
11. **Is Mac App Store distribution a future goal?** WKWebView is the safest path. Qt WebEngine explicitly does not support it; CEF would require separate policy/technical validation.
12. **What is the acceptable engine security-update SLA and app download size?** Choosing CEF/Electron/Qt means Fission—not the OS—must promptly redistribute browser security fixes.
13. **How many live tabs per Thread and globally?** Decide whether hidden tabs stay fully live, suspend, snapshot, or reload; measure rather than guess.
14. **Is deterministic rendering across OS versions more important than minimal size/native maintenance?** Bundled Chromium wins determinism; system WebKit wins operational simplicity.
15. **Does Fission intend to become a default browser?** If not, do not design around Apple's managed default-browser entitlement or promise entitlement-gated behavior.

## Sources

All sources below are first-party project/vendor documentation, source repositories, issue trackers, or licenses; accessed 2026-09-03.

### Apple / WebKit

- Apple, [`WKWebView`](https://developer.apple.com/documentation/webkit/wkwebview)
- Apple, [WebKit for AppKit and UIKit](https://developer.apple.com/documentation/webkit/webkit-for-appkit-and-uikit)
- Apple, [`WKWebViewConfiguration`](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration)
- Apple, [`WKWebsiteDataStore`](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [UUID initializer](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/init%28foridentifier%3A%29), [removal](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove%28foridentifier%3Acompletionhandler%3A%29)
- Apple, [`WKHTTPCookieStore`](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)
- Apple, [`WKNavigationDelegate`](https://developer.apple.com/documentation/webkit/wknavigationdelegate), [`WKUIDelegate`](https://developer.apple.com/documentation/webkit/wkuidelegate)
- Apple, [`WKDownload`](https://developer.apple.com/documentation/webkit/wkdownload), [`WKDownloadDelegate`](https://developer.apple.com/documentation/webkit/wkdownloaddelegate)
- Apple, [`WKUserContentController`](https://developer.apple.com/documentation/webkit/wkusercontentcontroller), [`WKContentWorld`](https://developer.apple.com/documentation/webkit/wkcontentworld)
- Apple, [`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler), [`WKContentRuleListStore`](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)
- Apple, [`NSViewRepresentable`](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)
- Apple, [Preparing your app to be the default web browser](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)
- Apple, [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [creating distribution-signed code](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [notarization troubleshooting](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- Apple, [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime), [App Sandbox entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox)
- WebKit, [Tracking Prevention](https://webkit.org/tracking-prevention/), [App-Bound Domains](https://webkit.org/blog/10882/app-bound-domains/), [Storage Access API update](https://webkit.org/blog/11545/updates-to-the-storage-access-api/)

### Chromium Embedded Framework

- CEF, [repository/README](https://github.com/chromiumembedded/cef), [license](https://github.com/chromiumembedded/cef/blob/master/LICENSE.txt)
- CEF, [General Usage](https://chromiumembedded.github.io/cef/general_usage.html), [Branches and Building](https://chromiumembedded.github.io/cef/branches_and_building.html), [hands-on tutorial](https://github.com/chromiumembedded/cef/blob/master/docs/hands_on_tutorial.md)
- CEF, [automated build index](https://cef-builds.spotifycdn.com/index.html), [machine-readable index](https://cef-builds.spotifycdn.com/index.json), [cef-project sample](https://github.com/chromiumembedded/cef-project)
- CEF, [macOS generated build variables](https://github.com/chromiumembedded/cef/blob/master/cmake/cef_variables.cmake.in), [library loader](https://github.com/chromiumembedded/cef/blob/master/include/wrapper/cef_library_loader.h), [bundle/path settings](https://github.com/chromiumembedded/cef/blob/master/include/internal/cef_types.h)
- CEF API, [`CefBrowserHost`](https://cef-builds.spotifycdn.com/docs/146.0/classCefBrowserHost.html), [`CefRequestContext`](https://cef-builds.spotifycdn.com/docs/125.0/classCefRequestContext.html), [`CefCookieManager`](https://cef-builds.spotifycdn.com/docs/146.0/classCefCookieManager.html), [`CefClient`](https://cef-builds.spotifycdn.com/docs/146.0/classCefClient.html)
- CEF, [accessibility declarations](https://github.com/chromiumembedded/cef/blob/master/include/cef_browser.h), [macOS OSR VoiceOver issue #3595](https://github.com/chromiumembedded/cef/issues/3595)

### Alternatives

- Qt, [WebEngine overview](https://doc.qt.io/qt-6/qtwebengine-overview.html), [features](https://doc.qt.io/qt-6/qtwebengine-features.html), [platform notes](https://doc.qt.io/qt-6/qtwebengine-platform-notes.html), [deployment](https://doc.qt.io/qt-6/qtwebengine-deploying.html), [licensing](https://doc.qt.io/qt-6/qtwebengine-licensing.html), [macOS native embedding](https://doc.qt.io/qt-6/platform-integration.html)
- Electron, [process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [`WebContentsView`](https://www.electronjs.org/docs/latest/api/web-contents-view), [security](https://www.electronjs.org/docs/latest/tutorial/security), [macOS signing](https://www.electronjs.org/docs/latest/tutorial/code-signing)
- Ultralight, [repository](https://github.com/ultralight-ux/Ultralight), [supported web features](https://github.com/ultralight-ux/Ultralight/wiki/Supported-Web-Features), [pricing](https://ultralig.ht/pricing), [custom GPU driver](https://docs.ultralig.ht/docs/using-a-custom-gpudriver)
- Servo, [repository](https://github.com/servo/servo), [embedding overview](https://book.servo.org/embedding/overview.html), [embedding roadmap](https://github.com/servo/servo/issues/27579), [C embedding status discussion](https://github.com/servo/servo/discussions/32618)
- Mozilla, [GeckoView architecture](https://firefox-source-docs.mozilla.org/mobile/android/geckoview/contributor/geckoview-architecture.html), [GeckoView quick start](https://mozilla.github.io/geckoview/consumer/docs/geckoview-quick-start), [Gecko embedding internals](https://firefox-source-docs.mozilla.org/dom/navigation/embedding.html)
- Tauri/Wry, [Wry repository](https://github.com/tauri-apps/wry), [Tauri architecture](https://v2.tauri.app/concept/architecture/)
- Microsoft, [WebView2 documentation](https://learn.microsoft.com/microsoft-edge/webview2/), [macOS support request](https://github.com/MicrosoftEdge/WebView2Feedback/issues/1314)
- Chromium, [official embedder guidance](https://groups.google.com/a/chromium.org/g/chromium-dev/c/aGWheqrFUQw)
- Chrome, [remote debugging](https://developer.chrome.com/docs/devtools/remote-debugging/local-server), [DevTools Protocol Monitor](https://developer.chrome.com/docs/devtools/protocol-monitor)

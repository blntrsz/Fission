import { contextBridge } from "electron";

contextBridge.exposeInMainWorld("fission", {
	shell: "electron",
});

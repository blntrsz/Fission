import { app, BrowserWindow } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.dirname(fileURLToPath(import.meta.url));

const createWindow = (): void => {
	const window = new BrowserWindow({
		width: 960,
		height: 640,
		title: "Fission",
		webPreferences: {
			preload: path.join(packageRoot, "preload.js"),
			contextIsolation: true,
			nodeIntegration: false,
			sandbox: true,
		},
	});

	void window.loadFile(path.join(packageRoot, "index.html"));
};

void app.whenReady().then(() => {
	createWindow();

	app.on("activate", () => {
		if (BrowserWindow.getAllWindows().length === 0) {
			createWindow();
		}
	});

	if (process.env.ELECTRON_SMOKE === "1") {
		app.quit();
	}
});

app.on("window-all-closed", () => {
	if (process.platform !== "darwin") {
		app.quit();
	}
});

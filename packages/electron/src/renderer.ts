const status = document.querySelector("[data-status]");

if (status instanceof HTMLElement) {
	const shell = window.fission?.shell ?? "unknown";
	status.textContent = `Running in ${shell}.`;
}

declare global {
	interface Window {
		fission?: {
			shell: string;
		};
	}
}

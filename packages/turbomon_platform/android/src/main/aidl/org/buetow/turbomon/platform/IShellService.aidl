package org.buetow.turbomon.platform;

// Runs in Shizuku's process with ADB shell rights (see ShellService.kt).
interface IShellService {
    // Transaction code Shizuku reserves for tearing the service down.
    void destroy() = 16777114;

    // Runs `sh -c script` and returns its stdout; stderr is discarded.
    String exec(String script) = 1;
}

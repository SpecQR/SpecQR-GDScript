# Fresh Godot consumer

1. Copy this directory into a new location.
2. Copy the complete repository `addons/specqr` directory into the new project's `addons/specqr`.
3. Open/import `project.godot` using the standard Godot 4.3+ engine.
4. Run the main scene, or run `godot --headless --no-header --path /path/to/project`.

The scene generates Unicode and binary QR codes, validates GS1/Structured Append, constructs a native Image, decodes the library's scratch PNG using Godot, and compares every RGBA byte. It emits a JSON success/failure report and exits. This is an executable consumer test scene, not a graphical demo or a GPU texture-readback test.

`SPECQR_CONSUMER_REPORT` optionally selects a JSON report file; `SPECQR_CONSUMER_PNG` optionally saves the generated PNG. The verification runner uses these with `--quiet` to require empty engine stdout/stderr.

Applications can use the returned Image with their own Godot rendering code. The initial library does not include a Texture convenience adapter and makes no GPU readback, Web-export or untested-platform claim.

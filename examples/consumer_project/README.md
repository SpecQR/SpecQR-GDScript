# Fresh Godot consumer

A separate Godot project for testing a copied SpecQR addon.

1. この directory を新しい場所へコピーします。
2. リポジトリの `addons/specqr` directory 全体を、新しいプロジェクトの `addons/specqr` へコピーします。
3. 標準 Godot 4.3+ engine で `project.godot` を開くか import します。
4. main scene を実行するか、`godot --headless --no-header --path /path/to/project` を実行します。

この scene は、Unicode と binary の QR Code を生成し、GS1/Structured Append を検証し、native Image を構築します。また、ライブラリが自前で生成した PNG を Godot で復号し、RGBA の全 byte を比較します。成功・失敗の JSON レポートを出力して終了します。実行可能な consumer test scene であり、graphical demo や GPU texture-readback test ではありません。

`SPECQR_CONSUMER_REPORT` で任意の JSON レポートファイルを選び、`SPECQR_CONSUMER_PNG` で生成した PNG を任意に保存できます。検証 runner は、engine の stdout/stderr が空であることを要求するため、これらを `--quiet` とともに使います。

アプリケーションは、返された Image を自身の Godot 描画コードで利用できます。初期ライブラリは Texture の便利な adapter を含まず、GPU readback、Web export、未検証 platform の実測を主張しません。

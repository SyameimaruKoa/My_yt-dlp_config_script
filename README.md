# My yt-dlp config script

yt-dlp Nightlyと追加ツールのセットアップ、およびWindows・Linux共通のダウンロード設定と字幕変換スクリプトじゃ。

## 対応環境

| OS | セットアップ | 外部ツールの管理 |
| --- | --- | --- |
| Ubuntu 24.04 / 26.04、Debian 12 / 13（amd64） | `setup_yt-dlp.sh` | apt / Deno公式インストーラー / UMU |
| Bazzite | `setup_yt-dlp.sh` | Homebrew / Deno公式インストーラー / インストール済みProton |
| Windows 10 / 11 | `setup_yt-dlp.ps1` | venvのpip（ffmpeg未導入時） / aria2公式ZIP（未導入時） / Deno ZIP |

Python 3.11以上が必要じゃ。WindowsではPythonを準備しておくのじゃ。

## インストール・更新

### Linux（Ubuntu / Debian / Bazzite）

```bash
git clone https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git
cd My_yt-dlp_config_script
bash setup_yt-dlp.sh
```

yt-dlpとpip依存パッケージは、通常の`yt-dlp`コマンドを実行するたびに更新確認するのじゃ。セットアップスクリプト・設定を更新したい場合は、リポジトリで`git pull --ff-only`を実行してセットアップを再実行するぞ。

セットアップではffmpeg・aria2・Gitなどを準備し、yt-dlp NightlyとPython追加パッケージを**リポジトリ内の仮想環境**にインストールする。DenoとYTSubConverter.exe、Proton Prefixもリポジトリ内に配置するぞ。字幕変換はUMU / Proton経由で動作し、Bazziteでは既存のProtonを優先するのじゃ。`PROTON_PATH`で選択を上書きできる。

```bash
PROTON_PATH="/path/to/Proton" bash setup_yt-dlp.sh
```

設定ファイル `~/.config/yt-dlp/config` と字幕変換スクリプトは、このリポジトリのファイルへシンボリックリンクされる。以前のGistではなく、リポジトリ側の内容が使用されるのじゃ。

### Windows

リポジトリをクローンするかZIPを展開し、そのディレクトリでPowerShellを実行するのじゃ。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup_yt-dlp.ps1
```

自動で導入・設定されるもの：

- yt-dlp Nightlyと追加Pythonパッケージ（仮想環境内）
- 既存のffmpeg・ffprobeがあれば流用。足りなければvenv内のpipで`static-ffmpeg`を導入し、両実行ファイルを`.runtime/windows/bin`へリンクまたは配置
- aria2cがなければSHA-256を検証した公式ZIPから`.runtime/windows/bin`へ配置。Denoもリポジトリ内へ配置
- YTSubConverter.exe（`YTSC_PATH`へ登録）
- `yt-dlp config`から変換したWindows用設定（`%APPDATA%\yt-dlp\config`）
- `yt-dlp.cmd`とユーザーPATH（起動用ディレクトリはジャンクション）
- MPC-BEが検出された場合は専用`yt-dlp.exe`を自動生成（通常のyt-dlp設定は変更しない）

yt-dlpとpip依存パッケージの更新確認は、`yt-dlp`起動時に毎回自動実行される。セットアップ内容を更新する場合は、スクリプトを再実行するのじゃ。PATHの変更は新しいターミナルから有効になるぞ。

### MPC-BE連携（Windows）

MPC-BEが検出された場合、セットアップ時に次のファイルを生成するのじゃ。

```text
%APPDATA%\MPC-BE\yt-dlp\yt-dlp.exe
%APPDATA%\MPC-BE\yt-dlp\yt-dlp.shim
```

MPC-BE側の「実行可能ファイル」には`%APPDATA%\MPC-BE\yt-dlp\yt-dlp.exe`のフルパスを指定する。既に同じパスを設定していれば変更不要じゃ。

専用Shimの実体はリポジトリ内の`.runtime/windows/mpc-be/`に置き、上記ディレクトリからジャンクションで参照する。pip仮想環境の`Scripts\yt-dlp.exe`を呼び出し、`--ignore-config`を強制する。起動時のpip更新確認も実行し、通常の`yt-dlp`設定や`Register-CUIApplicationPath.ps1`は変更せんぞ。MPC-BEが未検出なら専用Shimは作成しない。


## Python仮想環境

| OS | 保存先 | `yt-dlp`の起動方法 |
| --- | --- | --- |
| Linux | `<リポジトリ>/.runtime/linux/venv` | `~/.local/bin/yt-dlp`（Ubuntu/Debianでは`/usr/local/bin/yt-dlp`もリンク） |
| Windows | `<リポジトリ>/.runtime/windows/venv` | `%LOCALAPPDATA%\yt-dlp\bin\yt-dlp.cmd`（ジャンクション経由） |

通常の `yt-dlp` コマンドが仮想環境のPythonを直接呼び出すため、`activate`は不要じゃ。システム全体のpip環境にはインストールしないぞ。`.runtime/`はGitの管理対象外じゃ。OS共用の依存パッケージ（apt / brew）はシステム側へ配置される。Windowsでは既存のffmpeg・ffprobe・aria2cを優先して使用し、必要時のみリポジトリ内へ追加する。

導入するpip extras：

- 共通：`yt-dlp[default,curl-cffi]`（依存する`yt-dlp-ejs`、`requests`、`certifi`、`websockets`、`mutagen`、`pycryptodomex`、`brotli`なども自動導入）
- Linux：さらに`secretstorage`（LinuxでChromium系ブラウザーのCookieを取得する際に利用）

Nightlyの取得にはpipの`--pre`を使う。pip版は`yt-dlp -U`では更新せず、起動時に仮想環境のpipで確認・更新するのじゃ。

## 起動時の自動更新

LinuxもWindowsも`yt-dlp`起動時に`tools/yt_dlp_auto_update.py`のコピーを呼び出す。仮想環境内で`pip install --upgrade --pre`を実行し、yt-dlp Nightlyと追加依存パッケージの更新を確認するのじゃ。

- 更新があればインストール後にダウンロード処理を開始する。
- 通信エラーや更新失敗時は、インストール済みの版でそのまま起動する。
- 同時に複数起動した場合は、更新処理が重複しないようにする。
- 起動のたびにPyPIへ確認するため、ネットワーク状況によって開始までに時間がかかる。
- 自動更新を一時的に省略するには環境変数`YT_DLP_SKIP_UPDATE=1`を指定する。

**Linux**

```bash
YT_DLP_SKIP_UPDATE=1 yt-dlp "https://www.youtube.com/watch?v=..."
```

**Windows（PowerShell）**

```powershell
$env:YT_DLP_SKIP_UPDATE = '1'
yt-dlp "https://www.youtube.com/watch?v=..."
Remove-Item Env:YT_DLP_SKIP_UPDATE
```

更新結果の詳細なpipログは`YT_DLP_UPDATE_DEBUG=1`を指定し、更新に失敗したときに表示できるぞ。

## 旧方式からの自動移行と削除

Linuxセットアップ完了時に`tools/migration/remove-standalone.sh --legacy-gist --legacy-runtime`を実行する。旧方式で配置した`~/.local/bin/yt-dlp`と`/usr/local/bin/yt-dlp`はリポジトリ内のpip仮想環境用ラッパーへのシンボリックリンクに置換される。旧venv・旧更新スクリプト・旧Proton Prefix・旧Deno本体を検出して整理し、新ラッパーは残すぞ。

旧方式で設定ファイルを取得していた`~/21141912fbacf40877f4cf877577e082`も、正しいGistのクローンで、ローカル変更・追加ファイル・未送信コミットがない場合だけ自動削除する。条件に合わない場合は保持するぞ。Windowsでは旧方式のLinux用Gistクローンは使用しない。旧Windows venv・自動更新スクリプト・字幕変換ツール・MPC-BE Shimは、新しいリポジトリ内の実体へ移行した後に整理する。

削除対象を事前に確認する場合や、手動で再実行する場合は以下じゃ。

```bash
bash tools/migration/remove-standalone.sh --legacy-gist --legacy-runtime --dry-run
bash tools/migration/remove-standalone.sh --legacy-gist --legacy-runtime
```

別の場所のyt-dlp単独版を調べる場合は`--path /path/to/yt-dlp`を指定するのじゃ。

## アンインストール

インストールで作ったリポジトリ内の実行環境とリンク、歴代の旧方式によるファイルを削除する。必要なら`--remove-repository`でGit作業ツリー自体も削除できる（未コミットの変更がある場合は保持）。`--dry-run`では削除せず結果を確認できるぞ。

**Linux**

```bash
bash uninstall_yt-dlp.sh --dry-run
bash uninstall_yt-dlp.sh
bash uninstall_yt-dlp.sh --remove-repository
```

**Windows（PowerShell）**

```powershell
.\uninstall_yt-dlp.ps1 --dry-run
.\uninstall_yt-dlp.ps1
.\uninstall_yt-dlp.ps1 --remove-repository
```

OS共用の依存パッケージ（ffmpeg・aria2・Git・Python・curlなど）は、他の用途でも使用するため一括削除しない。旧方式が導入したものとユーザーが既に導入していたものは、インストール時の記録がない限り区別できないのじゃ。

Windowsアンインストーラーは、削除対象がなくても「対象なし」と検査先を出力する。終了時にはPATH上に残る`yt-dlp`の場所と、既知の配置先にある実行ファイルも確認する。管理外と判定した実行ファイルは削除せず、場所のみ報告するぞ。

## ダウンロード速度の比較

通常のHTTP/FTPはaria2c（最大8接続）、DASH/HLSはyt-dlp内蔵ダウンローダー（最大8フラグメント並列）を利用する。

YouTubeが単一HTTPSストリームとして扱われる場合、DASH/HLS用の設定では速度が変わらない。速度を比較する場合は同じ動画で以下を個別に試すのじゃ。

```bash
yt-dlp --downloader native --concurrent-fragments 8 "https://youtu.be/I8WP8Y2tdYE"
yt-dlp --downloader aria2c "https://youtu.be/I8WP8Y2tdYE"
```

実行中のaria2cダウンロードを切り替える機能ではない。再開の互換性が保証されないため、切り替えるなら別の一時保存先で検証する。

## 使用方法

```bash
yt-dlp --version
yt-dlp "https://www.youtube.com/watch?v=..."
yt-dlp --ignore-config --help
```

Windowsでも同じ`yt-dlp`コマンドで使用できるのじゃ。コマンドが別のインストール済みyt-dlpを指している場合は、Linuxなら`type -a yt-dlp`、Windowsなら`where.exe yt-dlp`で優先順位を確認するぞ。

## 設定と字幕変換

- `yt-dlp config`：共通設定。FirefoxのCookie、字幕取得、サムネイル、メタデータ、aria2、ダウンロード品質・ファイル名などを定義。
- `run_sub_converter.sh`：LinuxでSRV3字幕を検出し、装飾付き字幕はProton経由のYTSubConverterでASSに、単純な字幕はSRTに変換。
- `run_sub_converter.ps1`：Windows版の字幕変換。YTSubConverter.exeを`YTSC_PATH`から検索。
- `convert_config.ps1`：Linux用設定の`--exec`や一時ファイルパスをWindows用へ変換し、`win yt-dlp config`を生成。

設定のLinux用Discord通知は`Koa_Discord_Message.sh`を呼び出す。通知が不要なら`yt-dlp config`内の該当`--exec`行をコメントアウトするのじゃ。Linuxでは`~/.local/bin`がPATHに含まれる新しいシェルを開いて実行するぞ。

## ヘルプ

```bash
bash setup_yt-dlp.sh --help
bash uninstall_yt-dlp.sh --help
bash run_sub_converter.sh --help
bash tools/migration/remove-standalone.sh --help
```

```powershell
.\setup_yt-dlp.ps1 --help
.\uninstall_yt-dlp.ps1 --help
.\convert_config.ps1 --help
.\run_sub_converter.ps1 -Help
```

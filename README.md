# My yt-dlp config script

yt-dlp Nightlyと追加ツールのセットアップ、およびWindows・Linux共通のダウンロード設定と字幕変換スクリプトじゃ。

## 対応環境

| OS | セットアップ | 外部ツールの管理 |
| --- | --- | --- |
| Ubuntu 24.04 / 26.04、Debian 12 / 13（amd64） | `z__setup_yt-dlp.sh` | apt / Deno公式インストーラー / UMU |
| Bazzite | `z__setup_yt-dlp.sh` | Homebrew / Deno公式インストーラー / インストール済みProton |
| Windows 10 / 11 | `z__setup_yt-dlp.ps1` | winget |

Python 3.11以上が必要じゃ。WindowsではPythonとwingetを準備しておくのじゃ。

## インストール・更新

### Linux（Ubuntu / Debian / Bazzite）

```bash
git clone https://github.com/SyameimaruKoa/My_yt-dlp_config_script.git
cd My_yt-dlp_config_script
bash z__setup_yt-dlp.sh
```

yt-dlpとpip依存パッケージは、通常の`yt-dlp`コマンドを実行するたびに更新確認するのじゃ。セットアップスクリプト・設定を更新したい場合は、リポジトリで`git pull --ff-only`を実行してセットアップを再実行するぞ。

セットアップではffmpeg・aria2・Gitなどを準備し、yt-dlp NightlyとPython追加パッケージを仮想環境にインストールする。DenoとYTSubConverter.exeも配置するぞ。字幕変換はUMU / Proton経由で動作し、Bazziteでは既存のProtonを優先するのじゃ。`PROTON_PATH`で選択を上書きできる。

```bash
PROTON_PATH="/path/to/Proton" bash z__setup_yt-dlp.sh
```

設定ファイル `~/.config/yt-dlp/config` と字幕変換スクリプトは、このリポジトリのファイルへシンボリックリンクされる。以前のGistではなく、リポジトリ側の内容が使用されるのじゃ。

### Windows

リポジトリをクローンするかZIPを展開し、そのディレクトリでPowerShellを実行するのじゃ。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\z__setup_yt-dlp.ps1
```

自動で導入・設定されるもの：

- yt-dlp Nightlyと追加Pythonパッケージ（仮想環境内）
- ffmpeg、aria2、Deno（不足時にwingetで導入）
- YTSubConverter.exe（`YTSC_PATH`へ登録）
- `yt-dlp config`から変換したWindows用設定（`%APPDATA%\yt-dlp\config`）
- `yt-dlp.cmd`とユーザーPATH
- MPC-BEが検出された場合は専用`yt-dlp.exe`を自動生成（通常のyt-dlp設定は変更しない）

yt-dlpとpip依存パッケージの更新確認は、`yt-dlp`起動時に毎回自動実行される。セットアップ内容を更新する場合は、スクリプトを再実行するのじゃ。PATHの変更は新しいターミナルから有効になるぞ。

### MPC-BE連携（Windows）

MPC-BEが検出された場合、セットアップ時に次のファイルを生成するのじゃ。

```text
%APPDATA%\MPC-BE\yt-dlp\yt-dlp.exe
%APPDATA%\MPC-BE\yt-dlp\yt-dlp.shim
```

MPC-BE側の「実行可能ファイル」には`%APPDATA%\MPC-BE\yt-dlp\yt-dlp.exe`のフルパスを指定する。既に同じパスを設定していれば変更不要じゃ。

専用Shimはpip仮想環境の`Scripts\yt-dlp.exe`を呼び出し、`--ignore-config`を強制する。起動時のpip更新確認も実行し、通常の`yt-dlp`設定や`Register-CUIApplicationPath.ps1`は変更せんぞ。MPC-BEが未検出なら専用Shimは作成しない。


## Python仮想環境

| OS | 保存先 | `yt-dlp`の起動方法 |
| --- | --- | --- |
| Linux | `~/.local/share/yt-dlp/venv`（`XDG_DATA_HOME`を指定した場合はその下） | `~/.local/bin/yt-dlp`（Ubuntu/Debianでは`/usr/local/bin/yt-dlp`も登録） |
| Windows | `%LOCALAPPDATA%\yt-dlp\venv` | `%LOCALAPPDATA%\yt-dlp\bin\yt-dlp.cmd` |

通常の `yt-dlp` コマンドが仮想環境のPythonを直接呼び出すため、`activate`は不要じゃ。システム全体のpip環境にはインストールしないぞ。

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

## 旧単独実行ファイルの削除（一度限り）

Linux用の移行スクリプトを`tools/migration/`に配置したのじゃ。**新しい仮想環境版のラッパーは削除しない**。Windowsでは旧単独版の導入を行っていないため、削除作業は不要じゃ。

**Linux**

```bash
bash tools/migration/remove-standalone.sh --dry-run
bash tools/migration/remove-standalone.sh
```

以前のインストーラーが使用した`~/.local/bin/yt-dlp`と`/usr/local/bin/yt-dlp`を確認し、単独配布されたZIP形式のyt-dlpだけ削除する。別の場所に置いた場合は`--path /path/to/yt-dlp`を指定するのじゃ。セットアップによって既にラッパーへ置換されていれば削除対象にはならん。

## 使用方法

```bash
yt-dlp --version
yt-dlp "https://www.youtube.com/watch?v=..."
yt-dlp --ignore-config --help
```

Windowsでも同じ`yt-dlp`コマンドで使用できるのじゃ。コマンドが別のインストール済みyt-dlpを指している場合は、Linuxなら`type -a yt-dlp`、Windowsなら`where.exe yt-dlp`で優先順位を確認するぞ。

## 設定と字幕変換

- `yt-dlp config`：共通設定。FirefoxのCookie、字幕取得、サムネイル、メタデータ、aria2、ダウンロード品質・ファイル名などを定義。
- `z__run_sub_converter.sh`：LinuxでSRV3字幕を検出し、装飾付き字幕はProton経由のYTSubConverterでASSに、単純な字幕はSRTに変換。
- `z__run_sub_converter.ps1`：Windows版の字幕変換。YTSubConverter.exeを`YTSC_PATH`から検索。
- `z__convert_config.ps1`：Linux用設定の`--exec`や一時ファイルパスをWindows用へ変換し、`win yt-dlp config`を生成。

設定のLinux用Discord通知は`Koa_Discord_Message.sh`を呼び出す。通知が不要なら`yt-dlp config`内の該当`--exec`行をコメントアウトするのじゃ。Linuxでは`~/.local/bin`がPATHに含まれる新しいシェルを開いて実行するぞ。

## ヘルプ

```bash
bash z__setup_yt-dlp.sh --help
bash z__run_sub_converter.sh --help
bash tools/migration/remove-standalone.sh --help
```

```powershell
.\z__setup_yt-dlp.ps1 --help
.\z__convert_config.ps1 --help
.\z__run_sub_converter.ps1 -Help
```

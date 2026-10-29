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

更新時はリポジトリで `git pull --ff-only` を実行し、同じセットアップスクリプトを再実行するのじゃ。

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

更新時も同じスクリプトを再実行すればよいぞ。PATHの変更は新しく開いたターミナルから有効になるのじゃ。

## Python仮想環境

| OS | 保存先 | `yt-dlp`の起動方法 |
| --- | --- | --- |
| Linux | `~/.local/share/yt-dlp/venv`（`XDG_DATA_HOME`を指定した場合はその下） | `~/.local/bin/yt-dlp`（Ubuntu/Debianでは`/usr/local/bin/yt-dlp`も登録） |
| Windows | `%LOCALAPPDATA%\yt-dlp\venv` | `%LOCALAPPDATA%\yt-dlp\bin\yt-dlp.cmd` |

通常の `yt-dlp` コマンドが仮想環境のPythonを直接呼び出すため、`activate`は不要じゃ。システム全体のpip環境にはインストールしないぞ。

導入するpip extras：

- 共通：`yt-dlp[default,curl-cffi]`（依存する`yt-dlp-ejs`、`requests`、`certifi`、`websockets`、`mutagen`、`pycryptodomex`、`brotli`なども自動導入）
- Linux：さらに`secretstorage`（LinuxでChromium系ブラウザーのCookieを取得する際に利用）

Nightlyの取得にはpipの`--pre`を使う。pipパッケージとして導入しているため、`yt-dlp -U`ではなくセットアップスクリプトで更新するのじゃ。

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
```

```powershell
.\z__setup_yt-dlp.ps1 --help
.\z__convert_config.ps1 --help
.\z__run_sub_converter.ps1 -Help
```

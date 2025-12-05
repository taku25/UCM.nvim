# UCM.nvim

# Unreal Class Manager 💓 Neovim

<table>
  <tr>
   <td><div align=center><img width="100%" alt="UCM New Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-new.png" /></div></td>
   <td><div align=center><img width="100%" alt="UCM Rename Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-delete.png" /></div></td>
  </tr>
</table>

`UCM.nvim` は、Unreal Engine のC++クラス管理（作成、ファイル切り替え、リネーム、削除、実装コード生成）を、Neovimから行うためのプラグインです。プロジェクト固有のルールに従って動作します。

[English](README.md) | [日本語 (Japanese)](README_ja.md)

-----

## ✨ 機能 (Features)

  * **データ駆動型アーキテクチャ**:
      * プロジェクト固有の複雑なフォルダ構造（例：`Public`/`Private`の分離）やクラス作成ルールを `conf.lua` で一元管理します。
      * クラスの作成、リネーム、削除、ヘッダー/ソースの切り替えは、これらの堅牢なルールに基づいて実行されます。
      * **注意:** 全ての操作はファイルシステムベースです。コード内のクラスシンボルのリネームはLSPなどを使用して行ってください。
  * **シームレスなUI統合**:
      * `new`、`rename`、`delete` コマンドのフロントエンドとして、[Telescope](https://github.com/nvim-telescope/telescope.nvim) や [fzf-lua](https://github.com/ibhagwan/fzf-lua) を自動的に検出して使用します。
      * 外部UIプラグインがインストールされていない場合は、NeovimネイティブのUIにフォールバックします。
  * **インテリジェントな実装生成**:
      * `:UCM copy_imp` コマンドは、カーソル下の関数宣言に対応するC++実装スタブを自動生成し、クリップボードにコピーします。
      * `UFUNCTION` マクロ、`virtual`/`override` キーワード、デフォルト引数（`= 0.f`）を賢く除去し、適切な箇所にクラススコープや `Super::` 呼び出しを自動的に追加します。
  * **スマートなインクルード**:
      * 現在のファイル、またはピッカーで選択したクラスの正しい `#include` パス（モジュールの `Public` や `Classes` フォルダからの相対パス）を自動計算し、クリップボードにコピーします。
  * **マクロ入力支援 (Macro Wizard)**:
      * Unreal Engineのリフレクションマクロ (`UPROPERTY`, `UFUNCTION` など) のためのインテリジェントな補完ウィザードを提供します。
      * 適切なスペシファイア（例: `EditAnywhere`, `BlueprintReadWrite`）を対話的に複数選択し、コードに直接挿入できます。

<table>
  <tr>
   <td>
   <div align=center>
   <img width="100%" alt="UCM new gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-new.gif" /><br>
   <code>:UCM new</code> コマンド
   </div>
   </td>
   <td>
   <div align=center>
   <img width="100%" alt="UCM rename gif" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/ucmui-rename.gif" /><br>
   <code>:UCM rename</code> コマンド
   </div>
   </td>
  </tr>
</table>

## 🔧 必要要件 (Requirements)

  * Neovim v0.11.3 以上
  * [**UNL.nvim**](https://github.com/taku25/UNL.nvim) (**必須**)
  * **オプション (UI体験の向上のために、導入を強く推奨):**
      * [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
      * [fzf-lua](https://github.com/ibhagwan/fzf-lua)
      * [fd](https://github.com/sharkdp/fd) (**`Telescope`や`fzf-lua`をUIとして使用する場合は必須**)

## 🚀 インストール (Installation)

お好みのプラグインマネージャーでインストールしてください。

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  'taku25/UCM.nvim',
  dependencies = {
    "taku25/UNL.nvim", -- 必須!
    -- どちらか一方 (オプション)
    "nvim-telescope/telescope.nvim",
    "ibhagwan/fzf-lua",
  },
  opts = {
    -- 必要に応じて設定してください
  },
}
````

## ⚙️ 設定 (Configuration)

`lazy.nvim`の`opts`テーブルで、プラグインの挙動をカスタマイズできます。

```lua
opts = {
  -- 使用するUIフロントエンドを選択します
  -- "auto": Telescope -> fzf-lua -> native の優先順位で自動選択
  -- "telescope": Telescopeを優先 (fdが必須)
  -- "fzf-lua": fzf-luaを優先 (fdが必須)
  -- "native": Neovim標準の vim.ui を使用 (fdは不要)
  ui_frontend = "auto",

  -- :UCM new コマンド実行時に、ファイル作成の確認UIを表示するかどうか
  confirm_on_new = true,

  -- 新規ヘッダーファイル作成時のコピーライト
  copyright_header_h = "// Copyright...",
  -- 新規ソースファイル作成時のコピーライト
  copyright_header_cpp = "// Copyright..",

  -- :UCM new 時に親クラスを省略した場合のデフォルト
  default_parent_class = "Actor",

  -- クラス作成のテンプレートルール
  template_rules = {
    {
      name = "Object",
      priority = 0,
      parent_regex = ".*", -- 全てのUObjectに対するデフォルト
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "Object",
      direct_includes = { '"UObject/Object.h"' },
    },
  },
  -- 対応するソース/ヘッダーファイルを検索するためのフォルダマッピングルール
  folder_rules = {
    -- 基本的な Public <-> Private マッピング
    { type = "header",  regex = "^[Pp]ublic$", replacement = "Private" },
    { type = "source",  regex = "^[Pp]rivate$", replacement = "Public" },
    { type = "header",  regex = "^[Cc]lasses$", replacement = "Sources" },
    { type = "source",  regex = "^[Ss]ources$", replacement = "Classes" },
    
    -- 非対称なルールの例
    -- { regex = "^Headers$", replacement = "Private" },
    -- { regex = "^Private$", replacement = "Headers" },
  },
}
```

## ⚡ 使い方 (Usage)

全てのコマンドは `:UCM` から始まります。引数がない場合はUIが起動します。

```viml
" 新しいクラスを直接作成します
:UCM new <ClassName> <ParentClass> [TargetDir]

" クラスファイルを直接削除します (拡張子は省略可)
:UCM delete <Relative/Path/To/File>

" クラスファイルを直接リネームします (拡張子は省略可)
:UCM rename <Relative/Path/To/File> <NewName>

" クラスを新しいディレクトリに移動します
:UCM move <Source/File/Path> <Target/Dir>

" ヘッダーファイル (.h) とソースファイル (.cpp) を切り替えます
:UCM switch

" カーソル下の関数宣言の実装コードを生成し、クリップボードにコピーします
:UCM copy_imp

" 現在のファイルの正しい相対 #include パスをクリップボードにコピーします
:UCM copy_include

" プロジェクト内のクラスを選択し、その #include パスをコピーします
:UCM copy_include!

" 現在の行のマクロコンテキスト (例: UPROPERTY) に対応するスペシファイアを挿入します
:UCM specifiers

" マクロの種類 (UPROPERTY/UFUNCTION等) を強制的に選択してスペシファイアを挿入します
:UCM specifiers!
```

## 🤖 API & 自動化 (Automation Examples)

`UCM.api`モジュールを使用して、`Neo-tree`のようなファイラーと連携できます。
全てのAPIの詳細は `:help ucm` で確認してください。

### 🌲 Neo-tree からクラスの作成・削除・リネームを行う

```lua
opts = {
  close_if_last_window  = true,
  -- Neo-tree のキーマッピング設定例
  filesystem = {
    use_libuv_file_watcher = true,
    window = {
      mappings = {
        ["<leader>n"] = function(state)
          local node = state.tree:get_node()
          require("UCM.api").new_class({ target_dir = node.path })
        end,
        ["<leader>d"] = function(state)
          -- Neo-treeから取得したパスを、そのままコマンドの引数として渡すだけ！
          local node = state.tree:get_node()
          require("UCM.api").delete_class({ file_path = node.path })
        end,
        ["<leader>r"] = function(state)
          local node = state.tree:get_node()
          require("UCM.api").rename_class({ file_path = node.path })
        end,
      },
    },
  },
},
```

## その他

Unreal Engine 関連プラグイン:

  * [**UnrealDev.nvim**](https://github.com/taku25/UnrealDev.nvim)
      * **推奨:** これら全てのUnreal Engine関連プラグインを一括で導入・管理できるオールインワンスイートです。
  * [**UNX.nvim**](https://github.com/taku25/UNX.nvim)
      * **標準搭載:** Unreal Engine開発に特化した専用のエクスプローラー＆サイドバーです。Neo-tree等に依存せず、プロジェクト構造、クラス概形、プロファイリング結果などを表示できます。
  * [UEP.nvim](https://github.com/taku25/UEP.nvim)
      * .uprojectを解析してファイルナビゲートなどを簡単に行えるようになります。
  * [UEA.nvim](https://github.com/taku25/UEA.nvim)
      * C++クラスがどのBlueprintアセットから使用されているかを検索します。
  * [UBT.nvim](https://github.com/taku25/UBT.nvim)
      * BuildやGenerateClangDataBaseなどを非同期でNeovim上から使えるようになります。
  * [UCM.nvim](https://github.com/taku25/UCM.nvim)
      * クラスの追加や削除がNeovim上からできるようになります。
  * [ULG.nvim](https://github.com/taku25/ULG.nvim)
      * UEのログやLiveCoding, stat fpsなどをNeovim上から操作できるようになります。
  * [USH.nvim](https://github.com/taku25/USH.nvim)
      * ushellをNeovimから対話的に操作できるようになります。
  * [USX.nvim](https://github.com/taku25/USX.nvim)
      * tree-sitter-unreal-cpp や tree-sitter-unreal-shader のハイライト設定などを補助するプラグインです。
  * [neo-tree-unl](https://github.com/taku25/neo-tree-unl.nvim)
      * もし [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) をお使いの場合は、こちらを使うことでIDEのようなプロジェクトエクスプローラーを表示できます。
  * [tree-sitter for Unreal Engine](https://github.com/taku25/tree-sitter-unreal-cpp)
      * UCLASSなどを含めてtree-sitterの構文木を使ってハイライトができます。
  * [tree-sitter for Unreal Engine Shader](https://github.com/taku25/tree-sitter-unreal-shader)
      * .usfや.ushなどのUnreal Shader用のシンタックスハイライトを提供します。

## 📜 ライセンス (License)

MIT License

Copyright (c) 2025 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


# UCM.nvim

# Unreal Class Manager 💓 Neovim

<table>
  <tr>
   <td><div align=center><img width="100%" alt="UCM New Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-new.png" /></div></td>
   <td><div align=center><img width="100%" alt="UCM Rename Class Interactive Demo" src="https://raw.githubusercontent.com/taku25/UCM.nvim/images/assets/main-image-delete.png" /></div></td>
  </tr>
</table>

`UCM.nvim` は、Unreal Engine のC++クラス管理（作成、ファイル切り替え、リネーム、削除）を、Neovimから行うためのプラグインです。



[English](./README.md) | [日本語](./README_ja.md)

---

## ✨ 機能 (Features)
*   **データ駆動設計**:
    * プロジェクト固有の複雑なフォルダ構造（`Public`/`Private`）や、多様なクラスのルールを`conf.lua`で一元管理しています
    * クラス作成、リネイム、削除、ソースとヘッダーの切り変えをルールベースで判定実行します
      **操作はファイルに関することです** 実際のクラスのリネイムなどはLSPなどを使って使ってください
*   **UI**
    * ファイル作成、リネイム、削除コマンド使用時にUIのフロントエンドとして[Telescope](https://github.com/nvim-telescope/telescope.nvim)や[fzf-lua](https://github.com/ibhagwan/fzf-lua)が自動で判定され使用されます
      明示的に指定することも可能です。どちらもインストールされていない場合はneovimネイティブが使用されます

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

*   Neovim v0.11.3 以上
*   **オプション (UI体験の向上のために、いずれかの導入を強く推奨):**
    *   [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
    *   [fzf-lua](https://github.com/ibhagwan/fzf-lua)
    *   [fd](https://github.com/sharkdp/fd) (**`Telescope`や`fzf-lua`をUI使用時は必須**)

## 🚀 インストール (Installation)

[lazy.nvim](https://github.com/folke/lazy.nvim)での設定例:

```lua
return {
  'taku25/UCM.nvim',
  dependencies = {
    "taku25/UNL.nvim", --!必須!
    -- どちらか
    "nvim-telescope/telescope.nvim",--オプション
    "ibhagwan/fzf-lua",--オプション
  },
  opts = {
    -- あなたの好みに合わせて設定してください
  },
}
```

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

  -- 新規ファイル作成時のheader用コピーライト
  copyright_header_h = "// Copyright...",
  -- 新規策維持のソース用コピーライト
  copyright_header_cpp = "// Copyright..",

  -- :CMD new時に親を選択しなかったときのデフォルト
  default_parent_class = Actor,

  -- クラス作成のテンプレート
  template_rules = {
    {
      name = "Object",
      priority = 0,
      parent_regex = ".*", -- Default for any UObject
      template_dir = "builtin",
      header_template = "UObject.h.tpl",
      source_template = "UObject.cpp.tpl",
      class_prefix = "U",
      uclass_specifier = "",
      base_class_name = "Object",
      direct_includes = { '"UObject/Object.h"' },
    },
  },
  -- ソースからヘッダー、ヘッダーからソースの検索するためのルール
  folder_rules =folder_rules = {
    -- Basic Public <-> Private mapping
    { type = "header",  regex = "^[Pp]ublic$", replacement = "Private" },
    { type = "source",  regex = "^[Pp]rivate$", replacement = "Public" },
    { type = "header",  regex = "^[Cc]lasses$", replacement = "Sources" },
    { type = "source",  regex = "^[Ss]ources$", replacement = "Classes" },
    
    -- Example of an asymmetric rule (as you pointed out)
    -- { regex = "^Headers$", replacement = "Private" },
    -- { regex = "^Private$", replacement = "Headers" },
  },

}
```

## ⚡ 使い方 (Usage)


### 1. `:UCM` 

引数がない場合はuiが起動します

```viml
:UCM new <ClassName> <ParentClass> [TargetDir] " 新しいクラスを直接作成
:UCM delete <Relative/Path/To/File>           " クラスファイルを直接削除 (拡張子省略可)
:UCM rename <Relative/Path/To/File> <NewName> " クラスファイルを直接リネーム (拡張子省略可)
:UCM move <移動元のファイルパス> <移動先のディレクトリ> " クラスを新しいディレクトリに移動
:UCM switch                                   " ヘッダー/ソースを切り替え
```

## 🤖 API & 自動化 (Automation Examples)
`UCM.api`モジュールを使って、`Neo-tree`のようなファイラーと連携できます。
すべてのAPIはdocumentで確認してください
```viml
:help ucm
```

### 🌲 neo-tree で選択したてクラス作成、クラスの削除、クラスのリネイム
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
              vim.api.nvim_echo({{ node.path, "Normal" }}, true, { err = false })
              require("UCM.api").delete_class({ file_path = node.path })
            end,
            ["<leader>r"] = function(state)
              local node = state.tree:get_node()
              require("UCM.api").rename_class(
                { file_path = node.path, })
            end,
          },
        },
      },
    },
```


## その他
Unreal Engine 関連プラグイン:

* [UEP](https://github.com/taku25/UEP.nvim)
  * urpojectを解析してファイルナビゲートなどを簡単に行えるようになります
* [UBT](https://github.com/taku25/UBT.nvim)
  * BuildやGenerateClangDataBaseなどを非同期でNeovim上から使えるようになります
* [UCM](https://github.com/taku25/UCM.nvim)
  * クラスの追加や削除がNeovim上からできるようになります。
* [ULG](https://github.com/taku25/ULG.nvim)
  * UEのログやliveCoding,stat fpsなどnvim上からできるようになります
* [USH](https://github.com/taku25/USH.nvim)
  * ushellをnvimから対話的に操作できるようになります
* [neo-tree-unl](https://github.com/taku25/neo-tree-unl.nvim)
  * IDEのようなプロジェクトエクスプローラーを表示できます。
* [tree-sitter for Unreal Engine](https://github.com/taku25/tree-sitter-unreal-cpp)
  * UCLASSなどを含めてtree-sitterの構文木を使ってハイライトができます。

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

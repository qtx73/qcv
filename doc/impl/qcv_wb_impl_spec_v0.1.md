# `qcv_wb.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

IDステージからの演算/CSR結果とLSUからのロードデータを受け取り、レジスタファイルへの最終的な書き込みデータとイネーブル信号を生成する組み合わせロジック。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)            |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :----------------------- |
| `clk_i`                | Input  | 1      | クロック信号 (v0.1では未使用)                    |                          |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (v0.1では未使用)              |                          |
| `en_wb_i`              | Input  | 1      | IDステージからの命令完了信号                     | `qcv_id_stage`          |
| `rf_waddr_id_i`        | Input  | 5      | IDステージからの書き込みアドレス (rd)            | `qcv_id_stage`          |
| `rf_wdata_id_i`        | Input  | 32     | IDステージからの書き込みデータ (ALU/CSR結果)     | `qcv_id_stage`          |
| `rf_we_id_i`           | Input  | 1      | IDステージからの書き込みイネーブル               | `qcv_id_stage`          |
| `rf_wdata_lsu_i`       | Input  | 32     | LSUからの書き込みデータ (ロードデータ)           | `qcv_load_store_unit` |
| `rf_we_lsu_i`          | Input  | 1      | LSUからの書き込みイネーブル                      | `qcv_load_store_unit` |
| `rf_waddr_wb_o`        | Output | 5      | レジスタファイルへの書き込みアドレス             | `qcv_register_file_ff`|
| `rf_wdata_wb_o`        | Output | 32     | レジスタファイルへの書き込みデータ               | `qcv_register_file_ff`|
| `rf_we_wb_o`           | Output | 1      | レジスタファイルへの書き込みイネーブル           | `qcv_register_file_ff`|
| `lsu_resp_valid_i`     | Input  | 1      | LSU応答有効フラグ (エラー判定用、v0.1では未使用) | `qcv_load_store_unit` |
| `lsu_resp_err_i`       | Input  | 1      | LSUエラーフラグ (エラー判定用、v0.1では未使用)   | `qcv_load_store_unit` |

*(注: パフォーマンスカウンタ関連ポート (`instr_*`, `perf_*`) はv0.1スコープ外)*

## 3. 内部主要ロジック

*   **書き込みアドレスパススルー:**
    *   `rf_waddr_wb_o = rf_waddr_id_i;`
*   **書き込みデータ選択MUX:**
    *   `rf_we_id_i` (IDステージからの書き込み要求) と `rf_we_lsu_i` (LSUからの書き込み要求) は、IDステージの制御ロジックにより相互排他的にアサートされることが保証されている（同時にHighになることはない）。
    *   `rf_we_id_i` がHighの場合、`rf_wdata_id_i` (ALU/CSR結果) を `rf_wdata_wb_o` に出力する。
    *   `rf_we_lsu_i` がHighの場合、`rf_wdata_lsu_i` (ロードデータ) を `rf_wdata_wb_o` に出力する。

*   **書き込みイネーブル生成:**
    *   `rf_we_wb_o = rf_we_id_i | rf_we_lsu_i;` (どちらか一方がHighの場合のみHighになる)

## 4. 簡略化 (v0.1)

*   パフォーマンスカウンタ関連のロジックは実装しない。
*   エラー発生時の書き込み抑制ロジックは、コントローラ側で `rf_we_id_i` / `rf_we_lsu_i` を制御することを前提とし、このモジュールでは考慮しない。
*   クロックとリセットはポートとしては存在するが、内部ロジックでは使用しない。

---

# `qcv_register_file_ff.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

RISC-Vの汎用レジスタ (x0-x31) を保持するフリップフロップベースのレジスタファイル。2つの非同期読み出しポートと1つの同期書き込みポートを持つ。

## 2. ポート (v0.1 スコープ)

| 信号名         | 方向   | 幅 | 説明                                       | 接続先 (主な)    |
| :------------- | :----- | :- | :----------------------------------------- | :--------------- |
| `clk_i`        | Input  | 1  | クロック信号                               |                  |
| `rst_ni`       | Input  | 1  | 非同期リセット信号 (Active Low)            |                  |
| `raddr_a_i`    | Input  | 5  | 読み出しポートAのアドレス (rs1)            | `qcv_id_stage`  |
| `rdata_a_o`    | Output | 32 | 読み出しポートAのデータ                    | `qcv_id_stage`  |
| `raddr_b_i`    | Input  | 5  | 読み出しポートBのアドレス (rs2)            | `qcv_id_stage`  |
| `rdata_b_o`    | Output | 32 | 読み出しポートBのデータ                    | `qcv_id_stage`  |
| `waddr_a_i`    | Input  | 5  | 書き込みポートAのアドレス (rd)             | `qcv_wb`        |
| `wdata_a_i`    | Input  | 32 | 書き込みポートAのデータ                    | `qcv_wb`        |
| `we_a_i`       | Input  | 1  | 書き込みポートAのイネーブル                | `qcv_wb`        |

*(注: `RV32E` パラメータ、`test_en_i` ポートはv0.1スコープ外)*

## 3. 内部主要ロジック

*   **レジスタ配列 (`rf_reg_q[31:1]`):**
    *   31個の32ビット幅レジスタをフリップフロップで実装。インデックス1から31に対応。
    *   `always_ff @(posedge clk_i or negedge rst_ni)` ブロックを使用。
    *   リセット時 (`rst_ni` がLow) に全レジスタをゼロクリア。
    *   クロックエッジで、対応する書き込みイネーブル (`we_a_dec[i]`) がHighの場合に `wdata_a_i` で更新。
*   **書き込みアドレスデコーダ (`we_a_dec[31:1]`):**
    *   `waddr_a_i` と `we_a_i` から、各レジスタ (1-31) への書き込みイネーブル信号を生成する組み合わせロジック。
    *   `waddr_a_i` が0の場合はどの `we_a_dec` もアサートされない。
*   **読み出しロジック:**
    *   `raddr_a_i` が0の場合は `32'b0` を出力。0以外の場合は `rf_reg_q[raddr_a_i]` を `rdata_a_o` に出力する組み合わせロジック。
    *   `raddr_b_i` が0の場合は `32'b0` を出力。0以外の場合は `rf_reg_q[raddr_b_i]` を `rdata_b_o` に出力する組み合わせロジック。

## 4. 簡略化 (v0.1)

*   `RV32E` パラメータは `0` (32レジスタ) 固定として実装。
*   `test_en_i` ポートは無視する。

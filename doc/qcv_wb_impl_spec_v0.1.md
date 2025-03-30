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
(以降、`qcv_register_file_ff.v` ... の実装仕様を順次追加していく)

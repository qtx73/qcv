# `qcv_load_store_unit.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

ID/EXステージからの要求に基づき、データメモリへのロード/ストアアクセスを実行し、データのアライメントと符号拡張を行う。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)    |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :--------------- |
| `clk_i`                | Input  | 1      | クロック信号                                     |                  |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)                  |                  |
| **データメモリ I/F**   |        |        |                                                  | データメモリ/キャッシュ |
| `data_req_o`           | Output | 1      | データメモリへの要求                             |                  |
| `data_gnt_i`           | Input  | 1      | データメモリからの許可                           |                  |
| `data_rvalid_i`        | Input  | 1      | データメモリからのデータ有効                     |                  |
| `data_err_i`           | Input  | 1      | データメモリからのエラー                         |                  |
| `data_addr_o`          | Output | 32     | データメモリアドレス (ワードアライン)            |                  |
| `data_we_o`            | Output | 1      | データメモリへの書き込みイネーブル               |                  |
| `data_be_o`            | Output | 4      | データメモリへのバイトイネーブル                 |                  |
| `data_wdata_o`         | Output | 32     | データメモリへの書き込みデータ (アライン済み)    |                  |
| `data_rdata_i`         | Input  | 32     | データメモリからの読み込みデータ                 |                  |
| **ID/EXステージ I/F**  |        |        |                                                  | `qcv_id_stage`, `qcv_ex_block` |
| `lsu_we_i`             | Input  | 1      | 書き込みイネーブル指示                           | `qcv_id_stage`  |
| `lsu_type_i`           | Input  | 2      | アクセスタイプ (Word/Half/Byte)                  | `qcv_id_stage`  |
| `lsu_wdata_i`          | Input  | 32     | 書き込みデータ (rs2)                             | `qcv_id_stage`  |
| `lsu_sign_ext_i`       | Input  | 1      | ロードデータの符号拡張要否                       | `qcv_id_stage`  |
| `lsu_rdata_o`          | Output | 32     | 読み込みデータ (アライン/拡張済み)               | `qcv_wb`        |
| `lsu_rdata_valid_o`    | Output | 1      | `lsu_rdata_o` 有効フラグ                         | `qcv_wb`        |
| `lsu_req_i`            | Input  | 1      | メモリアクセス要求                               | `qcv_id_stage`  |
| `adder_result_ex_i`    | Input  | 32     | 実効アドレス (EXブロックから)                    | `qcv_ex_block`  |
| `addr_incr_req_o`      | Output | 1      | ミスアライン時のアドレスインクリメント要求       | `qcv_id_stage`  |
| `addr_last_o`          | Output | 32     | 最後にアクセスしたアドレス (mtval用)             | `qcv_id_stage`  |
| `lsu_resp_valid_o`     | Output | 1      | LSU応答有効フラグ (アクセス完了/エラー)          | `qcv_id_stage`  |
| `load_err_o`           | Output | 1      | ロードエラー発生フラグ                           | `qcv_id_stage`  |
| `store_err_o`          | Output | 1      | ストアエラー発生フラグ                           | `qcv_id_stage`  |
| `busy_o`               | Output | 1      | LSUがビジー状態か                                | トップレベル     |

*(注: PMP関連ポート (`data_pmp_err_i`)、パフォーマンスカウンタ関連ポート (`perf_*`) はv0.1スコープ外)*

## 3. 内部主要ロジック

*   **アドレス計算:**
    *   入力アドレス (`adder_result_ex_i`) からワードアラインされたアドレス (`data_addr_w_aligned`) とオフセット (`data_offset`) を計算。
*   **バイトイネーブル生成 (`data_be`):**
    *   アクセスタイプ (`lsu_type_i`) とアドレスオフセット (`data_offset`) に基づき、書き込み時にアサートするバイトレーンを決定する組み合わせロジック。
    *   ミスアラインアクセス時は、1回目と2回目 (`handle_misaligned_q`) で異なるバイトイネーブルを生成。
*   **書き込みデータアライメント (`data_wdata`):**
    *   アドレスオフセット (`data_offset`) に基づき、`lsu_wdata_i` を回転させて `data_wdata_o` を生成する組み合わせロジック。
*   **読み込みデータ処理:**
    *   **ミスアライン用レジスタ (`rdata_q`):** ミスアラインロードの1回目のアクセスで読み込んだデータの上位バイトを保持するレジスタ。
    *   **制御情報レジスタ (`data_type_q`, `data_sign_ext_q`, `rdata_offset_q` など):** アクセスタイプ、符号拡張要否、オフセットなどを保持するレジスタ。メモリアクセス開始時に更新。
    *   **データ再構成/拡張ロジック:**
        *   `data_rdata_i` と `rdata_q` (ミスアライン時) を結合し、`rdata_offset_q` に基づいて目的のワード (`rdata_w_ext`) を再構成。
        *   `data_type_q` に応じてワード/ハーフワード/バイトを抽出し、`data_sign_ext_q` に基づいて符号拡張またはゼロ拡張を行い、`lsu_rdata_o` を生成する組み合わせロジック。
*   **メモリアクセスFSM (`ls_fsm_cs`, `ls_fsm_ns`):**
    *   状態: `IDLE`, `WAIT_GNT`, `WAIT_RVALID`, `WAIT_GNT_MIS`, `WAIT_RVALID_MIS`, `WAIT_RVALID_MIS_GNTS_DONE` など。
    *   `lsu_req_i` を受けて `IDLE` から遷移し、`data_req_o` をアサート。
    *   `data_gnt_i` を待つ状態 (`WAIT_GNT`, `WAIT_GNT_MIS`)。
    *   `data_rvalid_i` を待つ状態 (`WAIT_RVALID`, `WAIT_RVALID_MIS`, `WAIT_RVALID_MIS_GNTS_DONE`)。
    *   ミスアラインアクセス (`split_misaligned_access`) を検出し、2回のアクセスを制御する状態遷移。
    *   `data_rvalid_i` 受信時に `lsu_resp_valid_o` をアサートし、`IDLE` に戻る。
    *   エラー (`data_err_i`) 発生時も `lsu_resp_valid_o` をアサートし、エラーフラグ (`load_err_o`, `store_err_o`) を設定。
*   **エラー処理:**
    *   `data_err_i` をラッチし (`lsu_err_q`)、アクセスタイプ (`data_we_q`) に応じて `load_err_o` または `store_err_o` をアサート。
*   **その他:**
    *   `addr_last_o`: 例外発生時の `mtval` やミスアラインアクセス時のアドレス計算用に、最後にアクセスしたアドレスを保持・出力。
    *   `busy_o`: FSMが `IDLE` 以外の場合にアサート。

## 4. 簡略化 (v0.1)

*   PMP関連の入力 (`data_pmp_err_i`) は無視する。
*   パフォーマンスカウンタ関連の出力 (`perf_*`) はスタブ化。

---
(以降、`qcv_wb.v` ... の実装仕様を順次追加していく)

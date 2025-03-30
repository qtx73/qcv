# `qcv_id_stage.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

コアの制御中心。IFステージから命令を受け取り、デコード、レジスタ読み出し、実行ユニット (`qcv_ex_block`) への指示、CSR (`qcv_cs_registers`) アクセス、LSU (`qcv_load_store_unit`) へのリクエスト発行、例外処理、パイプライン制御（ストール、フラッシュ）を行う。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)        |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :------------------- |
| `clk_i`                | Input  | 1      | クロック信号                                     |                      |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)                  |                      |
| **IFステージ I/F**     |        |        |                                                  | `qcv_if_stage`      |
| `instr_valid_i`        | Input  | 1      | 命令有効フラグ                                   |                      |
| `instr_rdata_i`        | Input  | 32     | 命令データ                                       |                      |
| `instr_fetch_err_i`    | Input  | 1      | 命令フェッチエラー                               |                      |
| `pc_id_i`              | Input  | 32     | 命令PC                                           |                      |
| `instr_req_o`          | Output | 1      | 命令フェッチ要求 (コントローラから)              |                      |
| `instr_valid_clear_o`  | Output | 1      | IF/IDレジスタクリア指示 (コントローラから)       |                      |
| `id_in_ready_o`        | Output | 1      | IDステージ受け入れ可能フラグ (コントローラから)  |                      |
| `pc_set_o`             | Output | 1      | PC書き換え指示 (コントローラから)                |                      |
| `pc_mux_o`             | Output | 2      | 次PC選択信号 (コントローラから)                  |                      |
| `exc_pc_mux_o`         | Output | 1      | 例外PC選択信号 (コントローラから)                |                      |
| **EXブロック I/F**     |        |        |                                                  | `qcv_ex_block`      |
| `branch_decision_i`    | Input  | 1      | 分岐判定結果                                     |                      |
| `ex_valid_i`           | Input  | 1      | EXブロック結果有効フラグ                         |                      |
| `result_ex_i`          | Input  | 32     | EXブロック演算結果                               |                      |
| `alu_operator_ex_o`    | Output | 4      | ALU演算の種類                                    |                      |
| `alu_operand_a_ex_o`   | Output | 32     | ALUオペランドA                                   |                      |
| `alu_operand_b_ex_o`   | Output | 32     | ALUオペランドB                                   |                      |
| `instr_first_cycle_id_o`| Output | 1      | 命令の最初のサイクルか                           |                      |
| **LSU I/F**            |        |        |                                                  | `qcv_load_store_unit` |
| `lsu_resp_valid_i`     | Input  | 1      | LSU応答有効フラグ                                |                      |
| `lsu_load_err_i`       | Input  | 1      | LSUロードエラー                                  |                      |
| `lsu_store_err_i`      | Input  | 1      | LSUストアエラー                                  |                      |
| `lsu_req_o`            | Output | 1      | LSUへのメモリアクセス要求                        |                      |
| `lsu_we_o`             | Output | 1      | LSUへの書き込みイネーブル                        |                      |
| `lsu_type_o`           | Output | 2      | LSUアクセスタイプ (Word/Half/Byte)               |                      |
| `lsu_sign_ext_o`       | Output | 1      | LSUロードデータの符号拡張要否                    |                      |
| `lsu_wdata_o`          | Output | 32     | LSUへの書き込みデータ (rs2)                      |                      |
| **レジスタファイル I/F** |        |        |                                                  | `qcv_register_file_ff`|
| `rf_rdata_a_i`         | Input  | 32     | レジスタA読み出しデータ                          |                      |
| `rf_rdata_b_i`         | Input  | 32     | レジスタB読み出しデータ                          |                      |
| `rf_raddr_a_o`         | Output | 5      | レジスタA読み出しアドレス (rs1)                  |                      |
| `rf_raddr_b_o`         | Output | 5      | レジスタB読み出しアドレス (rs2)                  |                      |
| `rf_ren_a_o`           | Output | 1      | レジスタA読み出しイネーブル                      |                      |
| `rf_ren_b_o`           | Output | 1      | レジスタB読み出しイネーブル                      |                      |
| **CSR I/F**            |        |        |                                                  | `qcv_cs_registers`  |
| `priv_mode_i`          | Input  | 2      | 現在の特権モード (v0.1はMのみ)                   |                      |
| `illegal_csr_insn_i`   | Input  | 1      | 不正CSRアクセスエラー                            |                      |
| `csr_rdata_i`          | Input  | 32     | CSR読み出しデータ                                |                      |
| `csr_access_o`         | Output | 1      | CSRアクセス命令フラグ                            |                      |
| `csr_op_o`             | Output | 2      | CSR操作の種類                                    |                      |
| `csr_op_en_o`          | Output | 1      | CSR操作実行許可 (コントローラから)               |                      |
| `csr_save_if_o`        | Output | 1      | CSRへのPC保存指示 (IFステージPC)                 |                      |
| `csr_save_id_o`        | Output | 1      | CSRへのPC保存指示 (IDステージPC)                 |                      |
| `csr_save_cause_o`     | Output | 1      | CSRへの例外要因保存指示                          |                      |
| `csr_mtval_o`          | Output | 32     | CSRへの例外関連値保存指示                        |                      |
| `exc_cause_o`          | Output | 7      | 例外要因コード (コントローラから)                |                      |
| **WBステージ I/F**     |        |        |                                                  | `qcv_wb`            |
| `rf_waddr_id_o`        | Output | 5      | 書き込みレジスタアドレス (rd)                    |                      |
| `rf_wdata_id_o`        | Output | 32     | 書き込みデータ (ALU/CSR結果)                     |                      |
| `rf_we_id_o`           | Output | 1      | 書き込みイネーブル                               |                      |
| `en_wb_o`              | Output | 1      | WBステージ有効化 (命令完了)                      |                      |
| `instr_id_done_o`      | Output | 1      | IDステージでの命令処理完了                       |                      |

## 3. 内部主要ロジック

*   **デコーダ (`qcv_decoder`) のインスタンス化:**
    *   IFステージからの命令 (`instr_rdata_i`) を入力とし、各種制御信号を生成する `qcv_decoder` モジュールをインスタンス化する。(v0.1では `qcv_decoder.v` を別途実装)
    *   生成される信号: ALU演算種類 (`alu_operator`)、オペランド選択 (`alu_op_a_mux_sel_dec`, `alu_op_b_mux_sel_dec`)、即値種類 (`imm_a_mux_sel`, `imm_b_mux_sel_dec`)、レジスタファイル制御 (`rf_we_dec`, `rf_raddr_a_o`, `rf_raddr_b_o`, `rf_waddr_o`, `rf_ren_a_dec`, `rf_ren_b_dec`)、LSU制御 (`lsu_req_dec`, `lsu_we`, `lsu_type`, `lsu_sign_ext`)、CSRアクセス (`csr_access_o`, `csr_op_o`)、分岐/ジャンプ種別 (`jump_in_dec`, `branch_in_dec`)、不正命令 (`illegal_insn_dec`) など。
*   **コントローラ (`qcv_controller`) のインスタンス化:**
    *   デコーダからの情報、IFステージからの情報、各実行ユニットからの状態を受け取り、パイプライン全体を制御する `qcv_controller` モジュールをインスタンス化する。(v0.1では `qcv_controller.v` を別途実装)
    *   IFステージへの制御信号 (`pc_set_o`, `pc_mux_o`, `exc_pc_mux_o`, `instr_valid_clear_o`, `id_in_ready_o`) を生成。
    *   例外/割り込み処理の制御 (`exc_cause_o`, `csr_save_*`, `csr_restore_*`)。
    *   ストール信号 (`stall_id`) の生成ロジックを含む。
*   **レジスタファイルインターフェース:**
    *   デコーダからの指示に基づき、レジスタファイルへの読み出しアドレス (`rf_raddr_a_o`, `rf_raddr_b_o`) とイネーブル (`rf_ren_a_o`, `rf_ren_b_o`) を生成。
    *   レジスタファイルからの読み出しデータ (`rf_rdata_a_i`, `rf_rdata_b_i`) を受け取る。
    *   ライトバックデータ選択 (`rf_wdata_sel`) とデコーダからの書き込みイネーブル (`rf_we_dec`)、コントローラからの実行許可 (`instr_executing`) に基づき、最終的な書き込みデータ (`rf_wdata_id_o`) とイネーブル (`rf_we_id_o`) を `qcv_wb` へ渡す。
*   **オペランド選択ロジック:**
    *   デコーダからの選択信号 (`alu_op_a_mux_sel`, `alu_op_b_mux_sel`, `imm_a_mux_sel`, `imm_b_mux_sel`) に基づき、レジスタデータ (`rf_rdata_a_i`, `rf_rdata_b_i`)、PC (`pc_id_i`)、即値 (`imm_i_type`, `imm_s_type` など) からALUへの入力 (`alu_operand_a`, `alu_operand_b`) を生成する。
    *   (注: v0.1ではフォワーディングは不要)
*   **EXブロックインターフェース:**
    *   デコードされたALU演算 (`alu_operator`) と選択されたオペランド (`alu_operand_a`, `alu_operand_b`) を `qcv_ex_block` へ渡す (`alu_operator_ex_o`, `alu_operand_a_ex_o`, `alu_operand_b_ex_o`)。
    *   `qcv_ex_block` からの結果 (`result_ex_i`) と分岐判定 (`branch_decision_i`) を受け取る。
*   **LSUインターフェース:**
    *   デコーダからのLSU制御信号 (`lsu_req_dec`, `lsu_we`, `lsu_type`, `lsu_sign_ext`) と書き込みデータ (`rf_rdata_b_i`) を `qcv_load_store_unit` へ渡す (`lsu_req_o`, `lsu_we_o`, `lsu_type_o`, `lsu_sign_ext_o`, `lsu_wdata_o`)。ただし、コントローラが許可 (`data_req_allowed`) した場合のみ `lsu_req_o` をアサート。
    *   `qcv_load_store_unit` からの応答 (`lsu_resp_valid_i`) とエラー (`lsu_load_err_i`, `lsu_store_err_i`) を受け取り、コントローラへ渡す。
*   **CSRインターフェース:**
    *   デコーダからのCSRアクセス信号 (`csr_access_o`, `csr_op_o`) と書き込みデータ (`alu_operand_a`) を `qcv_cs_registers` へ渡す。コントローラからの実行許可 (`csr_op_en_o`) も渡す。
    *   `qcv_cs_registers` からの読み出しデータ (`csr_rdata_i`) とエラー (`illegal_csr_insn_i`) を受け取る。
*   **ID/EX 内部ステートマシン (`id_fsm_q`):**
    *   現在の命令が最初のサイクル (`FIRST_CYCLE`) か、複数サイクル目 (`MULTI_CYCLE`) かを管理。
    *   LSUアクセス、分岐成功、ジャンプなどのマルチサイクル動作を検出して状態遷移。
    *   コントローラへストール要因 (`stall_mem`, `stall_branch`, `stall_jump` など) を通知。
    *   命令完了 (`instr_done`) を判定。

## 3. 簡略化 (v0.1)

*   `qcv_decoder` と `qcv_controller` は、RV32I基本命令セット、基本的な例外（不正命令、メモリアクセスエラー）、分岐/ジャンプ、ロード/ストアのストール/フラッシュ処理に限定して実装する。
*   MULDIV関連のロジック (`mult_en_ex_o`, `div_en_ex_o` など) はスタブ化または削除。
*   圧縮命令関連の入力 (`instr_is_compressed_i`, `illegal_c_insn_i`) は無視。
*   割り込み関連のロジック (`irq_*`, `nmi_*`) はスタブ化または削除。
*   デバッグ関連のロジック (`debug_*`) はスタブ化または削除。
*   CSRアクセスは、例外処理に必要な最低限（`mepc`, `mcause`, `mtval`, `mstatus` の一部など）のみを考慮。
*   パフォーマンスカウンタ関連の出力 (`perf_*`) はスタブ化。
*   `fetch_enable_i` は無視。

## 4. `qcv_decoder.v` 実装仕様 (IDステージ内で使用)

### 4.1. 役割

IFステージから受け取った命令 (`instr_rdata_i`) をデコードし、IDステージ内の他のモジュールが必要とする制御信号を生成する組み合わせ回路。

### 4.2. ポート (qcv_decoder.sv ベース、v0.1スコープ)

| 信号名                 | 方向   | 幅     | 説明                                       |
| :--------------------- | :----- | :----- | :----------------------------------------- |
| `instr_rdata_i`        | Input  | 32     | デコード対象の命令                         |
| `illegal_insn_o`       | Output | 1      | 不正命令フラグ                             |
| `ebrk_insn_o`          | Output | 1      | EBREAK命令フラグ (v0.1スコープ外)          |
| `mret_insn_o`          | Output | 1      | MRET命令フラグ (v0.1スコープ外)            |
| `dret_insn_o`          | Output | 1      | DRET命令フラグ (v0.1スコープ外)            |
| `ecall_insn_o`         | Output | 1      | ECALL命令フラグ (v0.1スコープ外)           |
| `wfi_insn_o`           | Output | 1      | WFI命令フラグ (v0.1スコープ外)             |
| `jump_set_o`           | Output | 1      | JAL/JALR/FENCE.I の最初のサイクルを示す    |
| `imm_a_mux_sel_o`      | Output | 1      | ALUオペランドAの即値選択 (v0.1では主にZERO) |
| `imm_b_mux_sel_o`      | Output | 3      | ALUオペランドBの即値選択 (I/S/B/U/J/PC+4) |
| `imm_i_type_o`         | Output | 32     | I形式即値                                  |
| `imm_s_type_o`         | Output | 32     | S形式即値                                  |
| `imm_b_type_o`         | Output | 32     | B形式即値                                  |
| `imm_u_type_o`         | Output | 32     | U形式即値                                  |
| `imm_j_type_o`         | Output | 32     | J形式即値                                  |
| `zimm_rs1_type_o`      | Output | 32     | CSRアクセス用即値 (rs1フィールド)          |
| `rf_wdata_sel_o`       | Output | 1      | レジスタ書き込みデータ選択 (ALU結果/CSR結果) |
| `rf_we_o`              | Output | 1      | レジスタ書き込みイネーブル                 |
| `rf_raddr_a_o`         | Output | 5      | レジスタ読み出しアドレスA (rs1)            |
| `rf_raddr_b_o`         | Output | 5      | レジスタ読み出しアドレスB (rs2)            |
| `rf_waddr_o`           | Output | 5      | レジスタ書き込みアドレス (rd)              |
| `rf_ren_a_o`           | Output | 1      | レジスタA読み出しイネーブル                |
| `rf_ren_b_o`           | Output | 1      | レジスタB読み出しイネーブル                |
| `alu_operator_o`       | Output | 4      | ALU演算の種類                              |
| `alu_op_a_mux_sel_o`   | Output | 2      | ALUオペランドA選択 (RegA/PC/Imm)           |
| `alu_op_b_mux_sel_o`   | Output | 1      | ALUオペランドB選択 (RegB/Imm)              |
| `csr_access_o`         | Output | 1      | CSRアクセス命令フラグ                      |
| `csr_op_o`             | Output | 2      | CSR操作の種類 (Read/Write/Set/Clear)       |
| `data_req_o`           | Output | 1      | LSUへのメモリアクセス要求                  |
| `data_we_o`            | Output | 1      | LSUへの書き込みイネーブル                  |
| `data_type_o`          | Output | 2      | LSUアクセスタイプ (Word/Half/Byte)         |
| `data_sign_extension_o`| Output | 1      | LSUロードデータの符号拡張要否              |
| `jump_in_dec_o`        | Output | 1      | JAL/JALR/FENCE.I 命令フラグ                |
| `branch_in_dec_o`      | Output | 1      | 分岐命令フラグ                             |

### 4.3. 内部主要ロジック

*   **命令フィールドデコード:** `instr_rdata_i` の各フィールド (opcode, funct3, funct7, rs1, rs2, rd, imm) を抽出する。
*   **即値生成:** 各形式 (I/S/B/U/J) の即値を抽出し、符号拡張またはゼロ拡張を行う。
*   **メインデコードロジック (組み合わせ回路):**
    *   `opcode` に基づいて命令種別を大分類。
    *   各命令種別内で `funct3`, `funct7` などを用いて詳細な命令を特定。
    *   特定した命令に応じて、上記ポート仕様にある各種制御信号 (`alu_operator_o`, `rf_we_o`, `data_req_o` など) の値を決定する。
    *   RV32Iの仕様書に従い、各命令に対応する制御信号の真理値表を実装する。
    *   不正なオペコードやファンクションコードの組み合わせを検出し、`illegal_insn_o` をアサートする。
    *   RV32Eのレジスタチェックはv0.1では不要。
    *   CSRアクセス命令の場合、操作タイプ (`csr_op_o`) を決定する。ただし、rs1がx0の場合のRead-Modify-Write命令の特別処理 (`csr_op_o` を `CSR_OP_READ` に変更) も実装する。

### 4.4. 簡略化 (v0.1)

*   MULDIV関連の出力 (`mult_en_o`, `div_en_o` など) は常にLowとする。
*   圧縮命令関連の入力 (`illegal_c_insn_i`) は無視。
*   割り込み/デバッグ関連の特殊命令 (`mret`, `dret`, `ebreak`, `wfi`) のデコードは行うが、対応するフラグ出力のみとし、特別な制御はコントローラに委ねる。
*   Bitmanip拡張 (RV32B) 関連のデコードは行わない。

## 5. `qcv_controller.v` 実装仕様 (IDステージ内で使用)

### 5.1. 役割

デコーダからの情報、IFステージからの情報、各実行ユニットからの状態を受け取り、パイプライン全体（特にIFステージとID/EXステージ間の制御）を管理するステートマシン。

### 5.2. ポート (qcv_controller.sv ベース、v0.1スコープ)

| 信号名                 | 方向   | 幅     | 説明                                       |
| :--------------------- | :----- | :----- | :----------------------------------------- |
| `clk_i`                | Input  | 1      | クロック信号                               |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)            |
| `illegal_insn_i`       | Input  | 1      | デコーダからの不正命令フラグ               |
| `ecall_insn_i`         | Input  | 1      | デコーダからのECALLフラグ (v0.1スコープ外) |
| `mret_insn_i`          | Input  | 1      | デコーダからのMRETフラグ (v0.1スコープ外)  |
| `dret_insn_i`          | Input  | 1      | デコーダからのDRETフラグ (v0.1スコープ外)  |
| `wfi_insn_i`           | Input  | 1      | デコーダからのWFIフラグ (v0.1スコープ外)   |
| `ebrk_insn_i`          | Input  | 1      | デコーダからのEBREAKフラグ (v0.1スコープ外)|
| `csr_pipe_flush_i`     | Input  | 1      | CSR書き込みによるパイプラインフラッシュ要求|
| `instr_valid_i`        | Input  | 1      | IFステージからの命令有効フラグ             |
| `instr_fetch_err_i`    | Input  | 1      | IFステージからのフェッチエラー             |
| `pc_id_i`              | Input  | 32     | IFステージからの命令PC                     |
| `instr_valid_clear_o`  | Output | 1      | IF/IDレジスタクリア指示                    |
| `id_in_ready_o`        | Output | 1      | IDステージが次の命令を受け入れ可能か       |
| `controller_run_o`     | Output | 1      | IDステージの命令実行許可 (ストール判定用)  |
| `instr_req_o`          | Output | 1      | IFステージへの命令フェッチ要求             |
| `pc_set_o`             | Output | 1      | IFステージへのPC書き換え指示               |
| `pc_mux_o`             | Output | 2      | IFステージの次PC選択信号                   |
| `exc_pc_mux_o`         | Output | 1      | IFステージの例外PC選択信号                 |
| `exc_cause_o`          | Output | 7      | 例外要因コード                             |
| `load_err_i`           | Input  | 1      | LSUからのロードエラー                      |
| `store_err_i`          | Input  | 1      | LSUからのストアエラー                      |
| `branch_set_i`         | Input  | 1      | ID/EX FSMからの分岐成功フラグ              |
| `jump_set_i`           | Input  | 1      | ID/EX FSMからのジャンプフラグ              |
| `csr_save_if_o`        | Output | 1      | CSRへのPC保存指示 (IFステージPC)           |
| `csr_save_id_o`        | Output | 1      | CSRへのPC保存指示 (IDステージPC)           |
| `csr_restore_mret_id_o`| Output | 1      | MRETによるCSRリストア指示 (v0.1スコープ外) |
| `csr_restore_dret_id_o`| Output | 1      | DRETによるCSRリストア指示 (v0.1スコープ外) |
| `csr_save_cause_o`     | Output | 1      | CSRへの例外要因保存指示                    |
| `csr_mtval_o`          | Output | 32     | CSRへの例外関連値(不正命令/アドレス)保存指示 |
| `priv_mode_i`          | Input  | 2      | CSRからの現在の特権モード (v0.1はMのみ)    |
| `stall_id_i`           | Input  | 1      | ID/EX FSMからのストール要求                |
| `flush_id_o`           | Output | 1      | IDステージ内部フラッシュ指示 (例外発生時など) |

### 5.3. 内部主要ロジック

*   **状態管理:** コアの現在の状態（実行中、ストール中、例外処理中など）を管理する内部ステートマシン。
*   **ストール制御 (`id_in_ready_o`, `controller_run_o`):**
    *   `stall_id_i` (ID/EX FSMからのストール要求) がHighの場合、`id_in_ready_o` をLowにしてIFステージを停止させ、`controller_run_o` をLowにしてIDステージの実行を停止する。
    *   例外処理中なども同様にストールさせる。
*   **例外検出と処理:**
    *   `illegal_insn_i`, `instr_fetch_err_i`, `load_err_i`, `store_err_i` などの例外要因を監視。
    *   例外発生を検出した場合:
        *   `pc_set_o` をアサートし、`pc_mux_o` を `PC_EXC` に設定。
        *   `exc_pc_mux_o` を適切な値 (通常 `EXC_PC_EXC`) に設定。
        *   `exc_cause_o` に対応する例外コードを設定。
        *   `csr_save_if_o` または `csr_save_id_o` をアサートして `mepc` にPCを保存。
        *   `csr_save_cause_o` をアサートして `mcause` に例外コードを保存。
        *   必要に応じて `csr_mtval_o` に不正命令やメモリアドレスを設定。
        *   `instr_valid_clear_o` をアサートしてIF/IDレジスタをフラッシュ。
        *   `flush_id_o` をアサートしてIDステージ内部をフラッシュ。
        *   例外処理中はストールさせる。
*   **分岐/ジャンプ処理:**
    *   `branch_set_i` または `jump_set_i` がアサートされた場合:
        *   `pc_set_o` をアサートし、`pc_mux_o` を `PC_JUMP` に設定 (ターゲットアドレスはEXブロックからIFへ供給)。
        *   `instr_valid_clear_o` をアサートしてIF/IDレジスタをフラッシュ。
*   **命令フェッチ要求 (`instr_req_o`):** 基本的に常にHighとするか、より詳細な制御が必要な場合はコアの動作状態に応じて制御する (v0.1では単純化)。

### 5.4. 簡略化 (v0.1)

*   割り込み処理ロジックは実装しない。
*   デバッグ関連ロジックは実装しない。
*   `mret`, `dret`, `ecall`, `ebreak`, `wfi` 命令の処理は、例外発生（不正命令など）として扱うか、NOPとして扱う。
*   CSR書き込みによるフラッシュ (`csr_pipe_flush_i`) は無視するか、単純なストールとして扱う。
*   特権モードはMモード固定とする。

---
(以降、`qcv_ex_block.v` ... の実装仕様を順次追加していく)

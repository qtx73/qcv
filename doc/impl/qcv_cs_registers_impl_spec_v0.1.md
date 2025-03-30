# `qcv_cs_registers.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

RISC-Vの制御・状態レジスタ (CSR) を管理する。v0.1では、基本的な例外処理に必要なCSRの保持とアクセス、例外発生時の状態保存に限定する。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)    |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :--------------- |
| `clk_i`                | Input  | 1      | クロック信号                                     |                  |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)                  |                  |
| `hart_id_i`            | Input  | 32     | ハートID (mhartid用)                             | トップレベル     |
| `priv_mode_id_o`       | Output | 2      | 現在の特権モード (IDステージへ、v0.1はMのみ)     | `qcv_id_stage`  |
| `priv_mode_lsu_o`      | Output | 2      | 現在の特権モード (LSUへ、v0.1はMのみ)            | `qcv_id_stage`  |
| `csr_mtvec_o`          | Output | 32     | 例外ベクタベースアドレス                         | `qcv_if_stage`  |
| `csr_mtvec_init_i`     | Input  | 1      | mtvec初期化要求 (リセット時)                     | `qcv_if_stage`  |
| `boot_addr_i`          | Input  | 32     | ブートアドレス (mtvec初期値用)                   | トップレベル     |
| `csr_access_i`         | Input  | 1      | IDステージからのCSRアクセス要求                  | `qcv_id_stage`  |
| `csr_addr_i`           | Input  | 12     | アクセス対象CSRアドレス                          | `qcv_id_stage`  |
| `csr_wdata_i`          | Input  | 32     | CSR書き込みデータ                                | `qcv_id_stage`  |
| `csr_op_i`             | Input  | 2      | CSR操作の種類 (Read/Write/Set/Clear)             | `qcv_id_stage`  |
| `csr_op_en_i`          | Input  | 1      | CSR操作実行許可                                  | `qcv_id_stage`  |
| `csr_rdata_o`          | Output | 32     | CSR読み出しデータ                                | `qcv_id_stage`  |
| `csr_mstatus_mie_o`    | Output | 1      | MSTATUS.MIEビット (割り込み制御用、v0.1スコープ外)| `qcv_id_stage`  |
| `csr_mepc_o`           | Output | 32     | 例外リターンアドレス                             | `qcv_if_stage`  |
| `pc_if_i`              | Input  | 32     | IFステージのPC (例外時保存用)                    | `qcv_if_stage`  |
| `pc_id_i`              | Input  | 32     | IDステージのPC (例外時保存用)                    | `qcv_id_stage`  |
| `csr_save_if_i`        | Input  | 1      | 例外発生時のPC保存指示 (IFステージPC)            | `qcv_id_stage`  |
| `csr_save_id_i`        | Input  | 1      | 例外発生時のPC保存指示 (IDステージPC)            | `qcv_id_stage`  |
| `csr_save_cause_i`     | Input  | 1      | 例外発生時の要因保存指示                         | `qcv_id_stage`  |
| `csr_mcause_i`         | Input  | 7      | 例外要因コード                                   | `qcv_id_stage`  |
| `csr_mtval_i`          | Input  | 32     | 例外関連値 (不正命令/アドレス)                   | `qcv_id_stage`  |
| `illegal_csr_insn_o`   | Output | 1      | 不正CSRアクセスエラー                            | `qcv_id_stage`  |

*(注: 割り込み、デバッグ、PMP、パフォーマンスカウンタ関連ポートはv0.1スコープ外)*

## 3. 内部主要ロジック

*   **CSRレジスタ:**
    *   `mstatus_q`: マシン状態レジスタ (v0.1ではMIE, MPIE, MPPフィールドの基本的な動作のみ)。
    *   `mepc_q`: マシン例外プログラムカウンタ。
    *   `mcause_q`: マシン例外原因レジスタ。
    *   `mtval_q`: マシン例外付加情報レジスタ。
    *   `mtvec_q`: マシン例外ベクタベースアドレスレジスタ。
    *   `mscratch_q`: マシンスクラッチレジスタ (読み書きのみ)。
    *   `mhartid_i`: ハートID (読み出し専用)。
    *   `misa_q`: ISAと拡張 (固定値)。
    *   その他 (`mie`, `mip`, `dcsr`, `depc`, PMP, パフォーマンスカウンタなど) はv0.1ではスタブまたは未実装。
*   **CSR読み出しロジック (`csr_rdata_int`):**
    *   `csr_addr_i` に基づき、対応する内部CSRレジスタの値を選択して `csr_rdata_o` に出力する組み合わせロジック。
    *   読み出し専用CSR (misa, mhartidなど) は固定値を出力。
    *   未実装CSRへのアクセスは `illegal_csr` フラグをアサート。
*   **CSR書き込みロジック:**
    *   `csr_op_i` (WRITE/SET/CLEAR) と `csr_wdata_i`, `csr_rdata_o` から、実際に書き込むデータ (`csr_wdata_int`) を計算する組み合わせロジック。
    *   `csr_we_int = (csr_op_i != CSR_OP_READ) & csr_op_en_i & ~illegal_csr_insn_o` を計算。
    *   `csr_addr_i` と `csr_we_int` に基づき、対応するCSRレジスタの次状態 (`_d`) と書き込みイネーブル (`_en`) を生成。
    *   各CSRレジスタは `always_ff` ブロックで実装し、対応する `_en` がHighの時に `_d` の値で更新。
*   **例外処理ロジック:**
    *   `csr_save_cause_i` がアサートされた場合:
        *   `mepc_en` をアサートし、`mepc_d` に `csr_save_if_i` または `csr_save_id_i` に応じて `pc_if_i` または `pc_id_i` を設定。
        *   `mcause_en` をアサートし、`mcause_d` に `csr_mcause_i` を設定。
        *   `mtval_en` をアサートし、`mtval_d` に `csr_mtval_i` を設定。
        *   `mstatus_en` をアサートし、`mstatus_d` のMIEを0に、MPIEに現在のMIEを、MPPに現在の特権モードを設定。
        *   特権モード (`priv_lvl_d`) をMモードに設定。
*   **リセット処理:**
    *   `rst_ni` がLowの場合、各CSRを仕様に基づいた初期値に設定。
    *   `mtvec_q` は `csr_mtvec_init_i` アサート時に `boot_addr_i` ベースの値で初期化。
*   **不正アクセス検出 (`illegal_csr_insn_o`):**
    *   未実装CSRへのアクセス (`illegal_csr`)。
    *   書き込み不可CSRへの書き込み (`illegal_csr_write`)。
    *   要求特権レベル未満でのアクセス (`illegal_csr_priv`)。
    *   これらのいずれかが発生した場合に `illegal_csr_insn_o` をアサート。

## 4. 簡略化 (v0.1)

*   割り込み関連CSR (`mie`, `mip`) の機能は実装しない (レジスタ自体は存在してもよい)。
*   デバッグ関連CSR (`dcsr`, `depc`, `dscratch`, トリガ関連) は実装しない。
*   PMP関連CSR (`pmpcfg`, `pmpaddr`, `mseccfg`) は実装しない。
*   パフォーマンスカウンタ関連CSR (`mcycle`, `minstret`, `mhpmcounter`, `mcountinhibit`, `mhpmevent`) は実装しない。
*   `mret`, `dret` 命令によるCSRリストアロジックは実装しない。
*   特権モードはMモード固定とし、`mstatus.MPP` の書き込みはMモードのみ受け付ける。
*   `mstatus` の `MPRV`, `TW` フィールドは無視する。

---
(これですべての主要内部モジュールの実装仕様定義が完了)

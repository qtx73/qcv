# `qcv_if_stage.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

プログラムカウンタ(PC)の管理と、`qcv_prefetch_buffer` を介した命令フェッチ制御。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)        |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :------------------- |
| `clk_i`                | Input  | 1      | クロック信号                                     |                      |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)                  |                      |
| `boot_addr_i`          | Input  | 32     | ブートアドレス (リセット時の初期PC)                | トップレベル         |
| `req_i`                | Input  | 1      | コア動作許可 (v0.1では常にHighと仮定)            | トップレベル         |
| **命令メモリ I/F**     |        |        |                                                  | 命令メモリ/キャッシュ |
| `instr_req_o`          | Output | 1      | 命令メモリへの要求 (プリフェッチバッファ経由)    |                      |
| `instr_addr_o`         | Output | 32     | 命令メモリアドレス (プリフェッチバッファ経由)    |                      |
| `instr_gnt_i`          | Input  | 1      | 命令メモリからの許可                             |                      |
| `instr_rvalid_i`       | Input  | 1      | 命令メモリからのデータ有効                       |                      |
| `instr_rdata_i`        | Input  | 32     | 命令メモリからのデータ                           |                      |
| `instr_err_i`          | Input  | 1      | 命令メモリからのエラー                           |                      |
| **IDステージ I/F**     |        |        |                                                  | `qcv_id_stage`      |
| `instr_valid_id_o`     | Output | 1      | IDステージへの命令有効フラグ                     |                      |
| `instr_new_id_o`       | Output | 1      | IDステージへの新規命令フラグ (RVFI用)            |                      |
| `instr_rdata_id_o`     | Output | 32     | IDステージへの命令データ                         |                      |
| `instr_fetch_err_o`    | Output | 1      | IDステージへのフェッチエラーフラグ               |                      |
| `pc_id_o`              | Output | 32     | IDステージへの命令PC                             |                      |
| `instr_valid_clear_i`  | Input  | 1      | IDステージからのIF/IDレジスタクリア指示          |                      |
| `pc_set_i`             | Input  | 1      | IDステージからのPC書き換え指示                   |                      |
| `pc_mux_i`             | Input  | 2      | IDステージからの次PC選択信号                     |                      |
| `exc_pc_mux_i`         | Input  | 1      | IDステージからの例外PC選択信号                   |                      |
| `exc_cause`            | Input  | 7      | IDステージからの例外要因 (v0.1では未使用)        |                      |
| `branch_target_ex_i`   | Input  | 32     | IDステージからの分岐/ジャンプターゲットアドレス  |                      |
| `id_in_ready_i`        | Input  | 1      | IDステージが受け入れ可能か                       |                      |
| **CSR I/F**            |        |        |                                                  | `qcv_cs_registers`  |
| `csr_mepc_i`           | Input  | 32     | 例外リターンアドレス (mret用、v0.1スコープ外)    |                      |
| `csr_depc_i`           | Input  | 32     | デバッグリターンアドレス (dret用、v0.1スコープ外) |                      |
| `csr_mtvec_i`          | Input  | 32     | 例外ベクタベースアドレス                         |                      |
| `csr_mtvec_init_o`     | Output | 1      | mtvec初期化要求 (リセット時)                     |                      |
| **その他**             |        |        |                                                  |                      |
| `if_busy_o`            | Output | 1      | IFステージがビジーか (プリフェッチバッファから)  | トップレベル         |

## 3. 内部主要ロジック

*   **PCレジスタ (`pc_q`, `pc_d`):** 現在の命令フェッチアドレスを保持する32ビットレジスタ。リセット時に `boot_addr_i` で初期化される。
*   **次PC選択ロジック:**
    *   通常時: `pc_q + 32'd4` を次PC候補とする。
    *   `pc_set_i` アサート時: `pc_mux_i` の値に応じて次PCを選択する組み合わせロジック。
        *   `PC_JUMP`: `branch_target_ex_i` (ID/EXステージからの分岐/ジャンプ先アドレス) を選択。
        *   `PC_EXC`: 例外発生時のハンドラアドレス (`exc_pc`) を選択 (v0.1では基本的な例外のみ考慮)。
        *   `PC_BOOT`, `PC_ERET`, `PC_DRET` などはv0.1スコープに応じて実装またはスタブ化。
    *   例外PC計算 (`exc_pc`): `exc_pc_mux_i` に基づき、`csr_mtvec_i` などから例外ハンドラアドレスを計算する組み合わせロジック (v0.1では基本的な例外のみ)。
*   **プリフェッチバッファ (`qcv_prefetch_buffer`) のインスタンス化と制御:**
    *   `qcv_prefetch_buffer` モジュールをインスタンス化する。
    *   `branch_i` ポートへ `pc_set_i` を接続し、PC変更時にバッファをフラッシュさせる。
    *   `addr_i` ポートへ計算された次PC (`fetch_addr_n`) を供給する。
    *   `req_i` ポートへ `req_i` (外部からのコア動作許可) を接続。
    *   `ready_i` ポートへ `id_in_ready_i` (次段の準備完了) を接続。
    *   プリフェッチバッファからの出力 (`fetch_valid`, `fetch_rdata`, `fetch_addr`, `fetch_err`) を受け取る。
    *   プリフェッチバッファのビジー信号 (`prefetch_busy`) を `if_busy_o` として出力。
*   **IF/ID パイプラインレジスタ:**
    *   `instr_valid_id_q`, `instr_valid_id_d`: IDステージへ渡す命令の有効フラグ。プリフェッチバッファからの `fetch_valid` がアサートされ、かつ `id_in_ready_i` がHighの時に `instr_valid_id_d` をHighにする。`instr_valid_clear_i` (IDステージからのフラッシュ要求) でクリアされる。
    *   `pc_id_o`: フェッチした命令に対応するPC (`fetch_addr`) を保持し、IDステージへ渡すレジスタ。`instr_valid_id_d` がHighになるタイミングで更新。
    *   `instr_rdata_id_o`: フェッチした命令 (`fetch_rdata`) を保持し、IDステージへ渡すレジスタ。`instr_valid_id_d` がHighになるタイミングで更新。
    *   `instr_fetch_err_o`: プリフェッチバッファからのメモリエラー (`fetch_err`) を保持し、IDステージへ渡すレジスタ。`instr_valid_id_d` がHighになるタイミングで更新。
    *   (注: `instr_rdata_alu_id_o`, `instr_rdata_c_id_o`, `instr_is_compressed_id_o`, `illegal_c_insn_id_o`, `instr_fetch_err_plus2_o` はv0.1では不要または簡略化)
*   **ストール/フラッシュ処理:**
    *   `id_in_ready_i` がLowの場合、IF/IDレジスタ更新を停止する (プリフェッチバッファへの `ready_i` 信号で制御)。
    *   `pc_set_i` がアサートされた場合（分岐/ジャンプ/例外）、プリフェッチバッファにフラッシュを指示 (`branch_i` ポート) し、IF/IDレジスタ内の命令を無効化 (`instr_valid_id_d` をLowにするか、`instr_valid_clear_i` を内部で生成するなど）し、新しいPCからのフェッチを開始する。

## 3. 簡略化 (v0.1)

*   `qcv_compressed_decoder` は実装せず、圧縮命令は非対応とする。
*   PMP関連の入力 (`pmp_err_if_i`, `pmp_err_if_plus2_i`) は無視する。
*   `test_en_i` は無視する。

## 4. `qcv_prefetch_buffer.v` 実装仕様 (IFステージ内で使用)

### 4.1. 役割

IFステージと命令メモリインターフェースの間に位置し、命令を先読みしてバッファリングする。分岐時にはバッファをフラッシュする。

### 4.2. ポート (qcv_prefetch_buffer.sv ベース)

| 信号名             | 方向   | 幅     | 説明                                       |
| :----------------- | :----- | :----- | :----------------------------------------- |
| `clk_i`            | Input  | 1      | クロック信号                               |
| `rst_ni`           | Input  | 1      | 非同期リセット信号 (Active Low)            |
| `req_i`            | Input  | 1      | IFステージからのフェッチ許可               |
| `branch_i`         | Input  | 1      | 分岐/ジャンプ発生フラグ (バッファフラッシュトリガ) |
| `addr_i`           | Input  | 32     | 分岐/ジャンプ先のターゲットアドレス        |
| `ready_i`          | Input  | 1      | 次段(IF/IDレジスタ)がデータ受け入れ可能    |
| `valid_o`          | Output | 1      | 出力データ(`rdata_o`, `addr_o`)が有効      |
| `rdata_o`          | Output | 32     | フェッチした命令データ                     |
| `addr_o`           | Output | 32     | `rdata_o`に対応する命令アドレス            |
| `err_o`            | Output | 1      | `rdata_o`に対応するメモリエラー            |
| `err_plus2_o`      | Output | 1      | (v0.1では未使用)                           |
| `instr_req_o`      | Output | 1      | 命令メモリへの要求                         |
| `instr_gnt_i`      | Input  | 1      | 命令メモリからの許可                       |
| `instr_addr_o`     | Output | 32     | 命令メモリへのアドレス                     |
| `instr_rdata_i`    | Input  | 32     | 命令メモリからのデータ                     |
| `instr_err_i`      | Input  | 1      | 命令メモリからのエラー                     |
| `instr_rvalid_i`   | Input  | 1      | 命令メモリからのデータ有効                 |
| `busy_o`           | Output | 1      | バッファがメモリ応答待ち、または要求発行中 |

### 4.3. 内部主要ロジック (v0.1 簡略版)

*   **内部FIFO:**
    *   深さ2程度のFIFOを想定 (`NUM_REQS = 2`)。各エントリは命令データ、アドレス、エラーフラグを保持。
    *   `branch_i` でFIFOの内容をクリアする。
    *   メモリ応答 (`instr_rvalid_i`) があり、かつ破棄フラグが立っていない場合に、受信データ (`instr_rdata_i`, `instr_addr_o`に対応するアドレス, `instr_err_i`) をFIFOに書き込む。
    *   `ready_i` がHighの場合にFIFOからデータを読み出し、`valid_o`, `rdata_o`, `addr_o`, `err_o` に出力する。
*   **要求発行ロジック:**
    *   `req_i` がHigh、FIFOに空きがあり、かつ未完了リクエスト数が上限 (`NUM_REQS`) 未満の場合に、メモリへ `instr_req_o` をアサートする。
    *   `instr_addr_o` は、最後に発行したアドレス (`fetch_addr_q`) または分岐先アドレス (`addr_i`) を基に計算する (通常は+4)。
*   **未完了リクエスト管理:**
    *   メモリに要求を発行してから応答 (`instr_rvalid_i`) を受け取るまでの間、リクエストが未完了であることを示すフラグ (`rdata_outstanding_q`) を管理する (シフトレジスタ等で実装)。
    *   `branch_i` が発生した場合、対応する未完了リクエストに破棄マーク (`branch_discard_q`) を付け、応答が来てもFIFOに入れないようにする。
*   **アドレス管理:**
    *   次にフェッチすべきアドレス (`fetch_addr_q`) を保持。通常は+4で更新、`branch_i` で `addr_i` に更新。
    *   メモリに発行中のアドレス (`stored_addr_q`) を保持。`instr_gnt_i` が来るまで保持。
*   **ビジー信号 (`busy_o`):** 未完了リクエストがある場合、または `instr_req_o` をアサートしている場合にHighとする。

### 4.4. 簡略化 (v0.1)

*   圧縮命令に関連する `err_plus2_o` のロジックは不要。
*   FIFOの実装は `qcv_fetch_fifo.sv` を参考に、Verilogで記述する。

---

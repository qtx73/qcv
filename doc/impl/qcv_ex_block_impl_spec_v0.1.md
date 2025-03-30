# `qcv_ex_block.v` 実装仕様書 (Verilog版) - v0.1

## 1. 役割

IDステージからの指示に基づき、算術論理演算 (ALU)、分岐ターゲットアドレス計算、ロード/ストアアドレス計算を行う。

## 2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             | 接続先 (主な)    |
| :--------------------- | :----- | :----- | :----------------------------------------------- | :--------------- |
| `clk_i`                | Input  | 1      | クロック信号                                     |                  |
| `rst_ni`               | Input  | 1      | 非同期リセット信号 (Active Low)                  |                  |
| **IDステージ I/F**     |        |        |                                                  | `cve2_id_stage`  |
| `alu_operator_i`       | Input  | 4      | ALU演算の種類                                    |                  |
| `alu_operand_a_i`      | Input  | 32     | ALUオペランドA                                   |                  |
| `alu_operand_b_i`      | Input  | 32     | ALUオペランドB                                   |                  |
| `alu_instr_first_cycle_i`| Input  | 1      | 命令の最初のサイクルか (マルチサイクルALU用)     |                  |
| `result_ex_o`          | Output | 32     | ALU演算結果                                      |                  |
| `branch_target_o`      | Output | 32     | 分岐/ジャンプターゲットアドレス                  |                  |
| `branch_decision_o`    | Output | 1      | 分岐条件判定結果                                 |                  |
| `ex_valid_o`           | Output | 1      | EXブロック結果有効フラグ                         |                  |
| **LSU I/F**            |        |        |                                                  | `qcv_load_store_unit` |
| `alu_adder_result_ex_o`| Output | 32     | 加算器結果 (主にアドレス計算用)                  |                  |

*(注: MULDIV関連ポート、RV32B関連ポート、中間値レジスタポート (`imd_val_*`) はv0.1スコープ外)*

## 3. 内部主要ロジック

*   **ALU (`qcv_alu`) のインスタンス化:**
    *   `qcv_alu.v` モジュールをインスタンス化する。(v0.1では `qcv_alu.v` を別途実装)
    *   IDステージからの `alu_operator_i`, `alu_operand_a_i`, `alu_operand_b_i` を接続する。
    *   `alu_instr_first_cycle_i` を接続する (v0.1ではマルチサイクルALU演算はないため影響小)。
*   **出力接続:**
    *   `qcv_alu` からの演算結果 (`alu_result`) を `result_ex_o` に接続する。
    *   `qcv_alu` からの加算器結果 (`adder_result_o`) を `alu_adder_result_ex_o` と `branch_target_o` に接続する。
    *   `qcv_alu` からの比較結果 (`comparison_result_o`) を `branch_decision_o` に接続する。
*   **有効信号 (`ex_valid_o`):**
    *   v0.1ではRV32I基本命令のみで、ALU演算は1サイクルで完了すると想定されるため、基本的には常にHighとする。
    *   (元のコードでは `~( |alu_imd_val_we )` となっており、マルチサイクルALU演算を考慮しているが、v0.1では不要)

## 4. 簡略化 (v0.1)

*   MULDIVユニット (`qcv_multdiv_slow`/`qcv_multdiv_fast`) はインスタンス化しない。
*   MULDIV関連の入力信号は無視する。
*   RV32B (Bitmanip拡張) に関連するロジックは実装しない。
*   マルチサイクル演算用の中間値レジスタ (`imd_val_*`) 関連ロジックは実装しない。

## 5. `qcv_alu.v` 実装仕様 (EXブロック内で使用)

### 5.1. 役割

IDステージから指示された算術論理演算を実行する組み合わせ回路。

### 5.2. ポート (v0.1 スコープ)

| 信号名                 | 方向   | 幅     | 説明                                             |
| :--------------------- | :----- | :----- | :----------------------------------------------- |
| `operator_i`           | Input  | 4      | 実行するALU演算の種類                            |
| `operand_a_i`          | Input  | 32     | オペランドA                                      |
| `operand_b_i`          | Input  | 32     | オペランドB                                      |
| `adder_result_o`       | Output | 32     | 加算器の結果 (アドレス計算、分岐ターゲット用)    |
| `result_o`             | Output | 32     | 最終的な演算結果                                 |
| `comparison_result_o`  | Output | 1      | 比較結果 (分岐条件判定用)                        |
| `is_equal_result_o`    | Output | 1      | オペランドAとBが等しいか (MULDIV用、v0.1では未使用)|

*(注: RV32B関連ポート、マルチサイクル演算関連ポート (`instr_first_cycle_i`, `imd_val_*`)、MULDIV関連ポート (`multdiv_*`) はv0.1スコープ外)*

### 5.3. 内部主要ロジック

*   **加算器/減算器:**
    *   `operand_a_i` と `operand_b_i` (またはその反転+1) を入力とする32ビット加算器。
    *   `operator_i` が減算または比較の場合、`operand_b_i` を反転してキャリー入力に1を設定する。
    *   結果を `adder_result_o` に出力。
*   **比較ロジック:**
    *   加算器の結果 (`adder_result_o`) とオペランドの符号ビット (`operand_a_i[31]`, `operand_b_i[31]`) を使用して、`operator_i` に応じた比較結果 (`comparison_result_o`) を生成する (EQ, NE, LT, GE, LTU, GEU)。
    *   `is_equal_result_o` は `adder_result_o` がゼロかどうかで判定。
*   **シフタ:**
    *   `operand_a_i` を `operand_b_i` の下位5ビットで指定された量だけシフトする。
    *   `operator_i` に応じて論理左シフト (SLL)、論理右シフト (SRL)、算術右シフト (SRA) を実行。
    *   結果を `shift_result` (内部信号) に格納。
*   **論理演算ユニット:**
    *   `operand_a_i` と `operand_b_i` のビット単位のAND, OR, XORを計算する。
    *   結果を `bwlogic_result` (内部信号) に格納。
*   **結果選択MUX:**
    *   `operator_i` に基づき、加算器結果 (`adder_result_o`)、シフタ結果 (`shift_result`)、論理演算結果 (`bwlogic_result`)、比較結果 (`comparison_result_o` をゼロ拡張したもの) などから最終的な出力 `result_o` を選択する。
    *   LUI命令の場合は `operand_b_i` (即値) をそのまま出力。
    *   AUIPC命令の場合は加算器結果 (`adder_result_o`) を出力。

### 5.4. 簡略化 (v0.1)

*   RV32B拡張に関連するすべてのロジック（ビット操作、パック、符号拡張、シングルビット、リバース、シャッフル、クロスバー、CRC、キャリーレス乗算、バタフライネットワークなど）は実装しない。
*   マルチサイクル演算のサポート（中間レジスタ `imd_val_*`）は不要。
*   MULDIVユニットとの連携ロジックは不要。

---
(以降、`qcv_load_store_unit.v` ... の実装仕様を順次追加していく)

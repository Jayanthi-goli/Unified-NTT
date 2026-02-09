/*module unif_bu_pipe #(
    parameter int WIDTH = 16,
    parameter int Q     = 3329
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [WIDTH-1:0]     a,
    input  logic [WIDTH-1:0]     b,
    input  logic [WIDTH-1:0]     w,
    input  logic                 sel,   // 0 = CT (fwd), 1 = GS (inv)
    output logic [WIDTH-1:0]     A_out,
    output logic [WIDTH-1:0]     B_out
);

    // =========================================================
    // Stage 0 - HOLD ORIGINAL a (CRITICAL FOR INVERSE GS)
    // =========================================================
    logic [WIDTH-1:0] a_hold;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            a_hold <= 0;
        else
            a_hold <= a;
    end

    // =========================================================
    // Stage 1 - Arithmetic (no reduction)
    // =========================================================
    logic [31:0] sum_raw;    // a+b  OR  a + b*w
    logic [31:0] diff_raw;   // a-b  OR  b-a
    logic [31:0] mul_raw;    // b*w  OR  (b-a)*w
    logic        sel_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_raw  <= 0;
            diff_raw <= 0;
            mul_raw  <= 0;
            sel_r    <= 0;
        end else begin
            sel_r <= sel;

            if (!sel) begin
                // ================= FORWARD CT =================
                // t = b * w
                mul_raw  <= b * w;
                sum_raw  <= a + (b * w);                 // a + t
                diff_raw <= a + Q - (b * w);             // a - t
            end else begin
                // ================= INVERSE GS =================
                // t = a_hold
                sum_raw  <= a_hold + b;                  // a + b
                diff_raw <= (b >= a_hold) ? (b - a_hold) // b - a
                                           : (b + Q - a_hold);
                mul_raw  <= 0; // filled next stage
            end
        end
    end

    // =========================================================
    // Stage 2 - Modular Reduction
    // =========================================================
    logic [15:0] sum_mod;
    logic [15:0] diff_mod;

    barrett_reduce_kyber br_sum  (.a(sum_raw),  .r(sum_mod));
    barrett_reduce_kyber br_diff (.a(diff_raw), .r(diff_mod));

    // =========================================================
    // Stage 3 - Multiply for Inverse GS
    // =========================================================
    logic [31:0] mul2_raw;
    logic [15:0] mul2_mod;

    always_ff @(posedge clk) begin
        mul2_raw <= diff_mod * w;   // w * (b - a)
    end

    barrett_reduce_kyber br_mul (.a(mul2_raw), .r(mul2_mod));

    // =========================================================
    // Stage 4 - Final Outputs
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_out <= 0;
            B_out <= 0;
        end else begin
            A_out <= sum_mod;
            B_out <= sel_r ? mul2_mod : diff_mod;
        end
    end

endmodule

`timescale 1ns/1ps
module unif_bu_pipe #(
    parameter int WIDTH = 16,
    parameter int Q     = 3329
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [WIDTH-1:0]     a,
    input  logic [WIDTH-1:0]     b,
    input  logic [WIDTH-1:0]     w,
    input  logic                 sel,   // 0 = CT (fwd), 1 = GS (inv)
    output logic [WIDTH-1:0]     A_out,
    output logic [WIDTH-1:0]     B_out
);

    // ======================
    // Stage 1
    // ======================
    logic [31:0] sum_raw;
    logic [31:0] diff_raw;
    logic [31:0] mul_raw;
    logic        sel_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_raw  <= 0;
            diff_raw <= 0;
            mul_raw  <= 0;
            sel_r    <= 0;
        end else begin
            sel_r <= sel;

            if (!sel) begin
                // ---------- FORWARD CT ----------
                // t = b * w
                diff_raw  <= b * w;
                sum_raw  <= a + (b * w);     // a + t
                mul_raw <= a + Q - (b * w); // a - t
            end else begin
                // ---------- INVERSE GS ----------
                // t = a
                sum_raw  <= a + b;           // a + b
                mul_raw  <= (b >= a) ? (b - a) * w
                                     : (b + Q - a) * w;
            end
        end
    end

    // ======================
    // Stage 2 (mod q)
    // ======================
    logic [15:0] sum_mod;
    logic [15:0] mul_mod;

    barrett_reduce_kyber br_sum (.a(sum_raw), .r(sum_mod));
    barrett_reduce_kyber br_mul (.a(mul_raw), .r(mul_mod));

    // ======================
    // Stage 3 (outputs)
    // ======================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_out <= 0;
            B_out <= 0;
        end else begin
            A_out <= sum_mod;
            B_out <= sel_r ? mul_mod : mul_mod; // same datapath
        end
    end

endmodule
*/

`timescale 1ns/1ps
module unif_bu_pipe #(
    parameter int WIDTH = 16,
    parameter int Q     = 3329
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             sel,     // 0 = CT (forward), 1 = GS (inverse)
    input  logic [WIDTH-1:0] a,       // f[j]
    input  logic [WIDTH-1:0] b,       // f[j+len]
    input  logic [WIDTH-1:0] w,       // zeta
    output logic [WIDTH-1:0] A_out,   // f[j]
    output logic [WIDTH-1:0] B_out    // f[j+len]
);

    // =====================================================
    // Stage 0 : latch t = a  (CRITICAL for GS correctness)
    // =====================================================
    logic [31:0] t;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            t <= 0;
        else
            t <= a;
    end

    // =====================================================
    // Stage 1 : core arithmetic (single multiplier reused)
    // =====================================================
    logic [31:0] bw;
    logic [31:0] s1_A, s1_B;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bw   <= 0;
            s1_A <= 0;
            s1_B <= 0;
        end else begin
            bw <= b * w;   // single multiplier (paper-style reuse)

            if (!sel) begin
                // ---------- Forward CT (Algorithm 9) ----------
                // t = w * b
                // f[j]     = a + t
                // f[j+len] = a - t
                s1_A <= a + bw;
                s1_B <= (a >= bw) ? (a - bw) : (a + Q - bw);

            end else begin
                // ---------- Inverse GS (Algorithm 10) ----------
                // t = a
                // f[j]     = t + b
                // f[j+len] = w * (b - t)
                s1_A <= t + b;
                s1_B <= (b >= t) ? (b - t) * w
                                 : (b + Q - t) * w;
            end
        end
    end

    // =====================================================
    // Stage 2 : Barrett reduction
    // =====================================================
    logic [WIDTH-1:0] red_A, red_B;

    barrett_reduce_kyber redA (.a(s1_A), .r(red_A));
    barrett_reduce_kyber redB (.a(s1_B), .r(red_B));

    // =====================================================
    // Stage 3 : output registers
    // =====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_out <= 0;
            B_out <= 0;
        end else begin
            A_out <= red_A;
            B_out <= red_B;
        end
    end

endmodule

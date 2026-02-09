`timescale 1ns/1ps
/*
module cu_fsm_pipe #(
    parameter int N = 256
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,   // 0 = Forward CT, 1 = Inverse GS

    // Load controls
    output logic        load_input_en,
    output logic [7:0]  load_input_addr,

    output logic        load_twiddle_en,
    output logic [7:0]  load_twiddle_addr,

    // Regbank read
    output logic [7:0]  rb1_raddr,
    output logic [7:0]  rb2_raddr,
    output logic [6:0]  rb3_raddr,   // 128 → 7 bits (FIXED)

    // Regbank write
    output logic [7:0]  rb1_waddr,
    output logic [7:0]  rb2_waddr,
    output logic        rb1_wen,
    output logic        rb2_wen,

    // BU select
    output logic        bu_sel,

    // Status
    output logic        done
);

    // =====================================================
    // FSM state
    // =====================================================
    typedef enum logic [2:0] {
        IDLE, LOAD_IN, LOAD_ZT, INIT, RUN, FINISH
    } state_t;

    state_t state;

    // =====================================================
    // Loop variables
    // =====================================================
    int        len, start_idx, j;
    logic [6:0] zeta_pos;      // FIXED width

    logic [7:0] cnt;
    logic [2:0] pipe_cnt;

    // Pipeline drain
    logic       draining;
    logic [1:0] drain_cnt;

    logic [7:0] waddr1_pipe [0:3];
    logic [7:0] waddr2_pipe [0:3];

    // =====================================================
    // SEQUENTIAL FSM + COUNTERS
    // =====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            done       <= 1'b0;
            cnt        <= 0;
            pipe_cnt   <= 0;
            draining   <= 0;
            drain_cnt  <= 0;
            rb1_wen    <= 0;
            rb2_wen    <= 0;
        end else begin
            // defaults
            rb1_wen <= 0;
            rb2_wen <= 0;
            done    <= 0;
            bu_sel  <= mode;

            case (state)

            // -------------------------------------------------
            IDLE: begin
                if (start) begin
                    cnt   <= 0;
                    state <= LOAD_IN;
                end
            end

            // -------------------------------------------------
            LOAD_IN: begin
                load_input_addr <= cnt;
                if (cnt == 8'd255) begin
                    cnt   <= 0;
                    state <= LOAD_ZT;
                end else
                    cnt <= cnt + 1;
            end

            // -------------------------------------------------
            LOAD_ZT: begin
                load_twiddle_addr <= cnt;
                if (cnt == 8'd127)
                    state <= INIT;
                else
                    cnt <= cnt + 1;
            end

            // -------------------------------------------------
            INIT: begin
                len       <= (mode == 0) ? (N >> 1) : 2;
                zeta_pos  <= (mode == 0) ? 7'd1 : 7'd127;
                start_idx <= 0;
                j         <= 0;
                pipe_cnt  <= 0;
                draining  <= 0;
                drain_cnt <= 0;
                state     <= RUN;
            end

            // -------------------------------------------------
            RUN: begin
                // READ addresses
                rb1_raddr <= start_idx + j;
                rb2_raddr <= start_idx + j + len;
                rb3_raddr <= zeta_pos;

                // Pipeline write address delay
                waddr1_pipe[0] <= start_idx + j;
                waddr2_pipe[0] <= start_idx + j + len;

                for (int k = 1; k < 4; k++) begin
                    waddr1_pipe[k] <= waddr1_pipe[k-1];
                    waddr2_pipe[k] <= waddr2_pipe[k-1];
                end

                // Enable writes after pipeline fill
                if (pipe_cnt < 3)
                    pipe_cnt <= pipe_cnt + 1;
                else begin
                    rb1_waddr <= waddr1_pipe[3];
                    rb2_waddr <= waddr2_pipe[3];
                    rb1_wen   <= 1'b1;
                    rb2_wen   <= 1'b1;
                end

                // Loop control
                if (!draining) begin
                    if (j == len - 1) begin
                        j <= 0;
                        start_idx <= start_idx + (len << 1);
                        zeta_pos  <= mode ? (zeta_pos - 1) : (zeta_pos + 1);

                        if (start_idx + (len << 1) >= N) begin
                            start_idx <= 0;
                            pipe_cnt  <= 0;

                            if ((!mode && len == 2) ||
                                ( mode && len == (N >> 1))) begin
                                draining  <= 1;
                                drain_cnt <= 0;
                            end else
                                len <= mode ? (len << 1) : (len >> 1);
                        end
                    end else
                        j <= j + 1;
                end
                // Drain pipeline
                else begin
                    if (drain_cnt < 2)
                        drain_cnt <= drain_cnt + 1;
                    else begin
                        draining <= 0;
                        state    <= FINISH;
                    end
                end
            end

            // -------------------------------------------------
            FINISH: begin
                done  <= 1'b1;
                state <= FINISH;
            end

            endcase
        end
    end

    // =====================================================
    // COMBINATIONAL CONTROL OUTPUTS (FIXED)
    // =====================================================
    always_comb begin
        load_input_en   = 1'b0;
        load_twiddle_en = 1'b0;

        case (state)
            LOAD_IN: load_input_en   = 1'b1;
            LOAD_ZT: load_twiddle_en = 1'b1;
            default: ;
        endcase
    end

endmodule
////
module cu_fsm_pipe_safe #(
    parameter int N        = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,     // 0 = forward CT, 1 = inverse GS

    output logic [7:0] base,
    output logic [7:0] j,
    output logic [7:0] len,
    output logic [6:0] zeta,
    output logic       bu_sel,
    output logic       wen,
    output logic       done
);

    typedef enum logic [2:0] {
        IDLE,
        ISSUE,
        WAIT,
        WRITE,
        NEXT,
        DRAIN,
        FINISH
    } state_t;

    state_t state;

    int wait_cnt;
    int drain_cnt;

    // --------------------------------------------------
    // FSM
    // --------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            base  <= 0;
            j     <= 0;
            len   <= 0;
            zeta  <= 0;
            wen   <= 0;
            done  <= 0;
            wait_cnt  <= 0;
            drain_cnt <= 0;
        end else begin
            // defaults
            wen  <= 0;
            done <= 0;
            bu_sel <= mode;

            case (state)

            // =================================================
            // IDLE
            // =================================================
            IDLE: begin
                if (start) begin
                    base <= 0;
                    j    <= 0;
                    len  <= mode ? 8'd2 : (N >> 1);
                    zeta <= mode ? 7'd127 : 7'd0;
                    state <= ISSUE;
                end
            end

            // =================================================
            // ISSUE: latch read indices (IMPORTANT)
            // =================================================
            ISSUE: begin
                wait_cnt <= 0;
                state <= WAIT;
            end

            // =================================================
            // WAIT: wait for pipelined BU
            // =================================================
            WAIT: begin
                if (wait_cnt == PIPE_LAT-1)
                    state <= WRITE;
                else
                    wait_cnt <= wait_cnt + 1;
            end

            // =================================================
            // WRITE: write butterfly outputs
            // =================================================
            WRITE: begin
                wen <= 1;
                state <= NEXT;
            end

            // =================================================
            // NEXT: update loop indices
            // =================================================
     NEXT: begin
    if (j == len-1) begin
        j <= 0;

        // move to next group
        base <= base + (len << 1);

        // -------- CORRECT zeta update --------
        // Update zeta ONLY when moving to a new group
        if (base + (len << 1) < N) begin
            if (!mode)
                zeta <= zeta + 1;   // forward NTT
            else
                zeta <= zeta - 1;   // inverse NTT
        end
        // ------------------------------------

        if (base + (len << 1) >= N) begin
            base <= 0;

            if ((!mode && len == 2) ||
                ( mode && len == (N >> 1))) begin
                drain_cnt <= 0;
                state <= DRAIN;
            end else begin
                len <= mode ? (len << 1) : (len >> 1);
                state <= ISSUE;
            end
        end else begin
            state <= ISSUE;
        end
    end else begin
        j <= j + 1;
        state <= ISSUE;
    end
end


            // =================================================
            // DRAIN: flush remaining pipeline results
            // =================================================
            DRAIN: begin
                if (drain_cnt < PIPE_LAT) begin
                    drain_cnt <= drain_cnt + 1;
                    wen <= 1;
                end else
                    state <= FINISH;
            end

            // =================================================
            // FINISH
            // =================================================
            FINISH: begin
                done <= 1;
            end

            endcase
        end
    end

endmodule
///
`timescale 1ns/1ps
module cu_fsm_pipe_safe #(
    parameter int N        = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,     // 0 = forward CT, 1 = inverse GS

    output logic [7:0] base,
    output logic [7:0] j,
    output logic [7:0] len,
    output logic [6:0] zeta,
    output logic       bu_sel,
    output logic       wen,
    output logic       done
);

    typedef enum logic [2:0] {
        IDLE,
        ISSUE,
        WAIT,
        WRITE,
        NEXT,
        FINISH
    } state_t;

    state_t state;

    int wait_cnt;

    // stage-level zeta base (CRITICAL)
    logic [6:0] zeta_base;

    // --------------------------------------------------
    // FSM
    // --------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            base  <= 0;
            j     <= 0;
            len   <= 0;
            zeta  <= 0;
            zeta_base <= 0;
            wen   <= 0;
            done  <= 0;
            wait_cnt <= 0;
            bu_sel <= 0;
        end else begin
            // defaults
            wen   <= 0;
            done  <= 0;
            bu_sel <= mode;

            case (state)

            // =================================================
            // IDLE
            // =================================================
            IDLE: begin
                if (start) begin
                    base <= 0;
                    j    <= 0;

                    if (!mode) begin
                        // ---------- FORWARD ----------
                        len <= N >> 1;      // 128
                        zeta_base <= 7'd1;
                    end else begin
                        // ---------- INVERSE ----------
                        len <= 8'd2;
                        zeta_base <= 7'd127;
                    end

                    zeta <= zeta_base;
                    state <= ISSUE;
                end
            end

            // =================================================
            // ISSUE (addresses are stable here)
            // =================================================
            ISSUE: begin
                wait_cnt <= 0;
                state <= WAIT;
            end

            // =================================================
            // WAIT for BU pipeline
            // =================================================
            WAIT: begin
                if (wait_cnt == PIPE_LAT-1)
                    state <= WRITE;
                else
                    wait_cnt <= wait_cnt + 1;
            end

            // =================================================
            // WRITE results
            // =================================================
            WRITE: begin
                wen <= 1;
                state <= NEXT;
            end

            // =================================================
            // NEXT (loop control)
            // =================================================
            NEXT: begin
                if (j == len-1) begin
                    j <= 0;
                    base <= base + (len << 1);

                    // advance zeta ONCE PER GROUP
                    if (!mode)
                        zeta <= zeta + 1;   // forward
                    else
                        zeta <= zeta - 1;   // inverse

                    if (base + (len << 1) >= N) begin
                        base <= 0;

                        // ---------- STAGE COMPLETE ----------
                        if (!mode) begin
                            // forward: len = 128 → 2
                            if (len == 8'd2) begin
                                state <= FINISH;
                            end else begin
                                len <= len >> 1;
                                zeta_base <= zeta_base + 1;
                                zeta <= zeta_base + 1;
                                state <= ISSUE;
                            end
                        end else begin
                            // inverse: len = 2 → 128
                            if (len == (N >> 1)) begin
                                state <= FINISH;
                            end else begin
                                len <= len << 1;

                                // EXACT Algorithm-10 zeta reset
                                case (len << 1)
                                    4:   zeta_base <= 7'd63;
                                    8:   zeta_base <= 7'd31;
                                    16:  zeta_base <= 7'd15;
                                    32:  zeta_base <= 7'd7;
                                    64:  zeta_base <= 7'd3;
                                    128: zeta_base <= 7'd1;
                                endcase

                                zeta <= zeta_base;
                                state <= ISSUE;
                            end
                        end
                    end else begin
                        state <= ISSUE;
                    end
                end else begin
                    j <= j + 1;
                    state <= ISSUE;
                end
            end

            // =================================================
            // FINISH
            // =================================================
            FINISH: begin
                done <= 1;
            end

            endcase
        end
    end

endmodule
///////////////
`timescale 1ns/1ps
module cu_fsm_pipe_safe #(
    parameter int N = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,

    output logic [7:0] rb1_raddr,
    output logic [7:0] rb2_raddr,
    output logic [6:0] rb3_raddr,

    output logic [7:0] rb1_waddr,
    output logic [7:0] rb2_waddr,
    output logic       rb1_wen,
    output logic       rb2_wen,

    output logic       bu_sel,
    output logic       done
);

    typedef enum logic [2:0] {
        IDLE, ISSUE, WAIT, WRITE, NEXT, DRAIN, FINISH
    } state_t;

    state_t state;

    int len, base, j;
    int wait_cnt, drain_cnt;
    logic [6:0] zeta;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            rb1_wen <= 0;
            rb2_wen <= 0;
            done <= 0;
        end else begin
            rb1_wen <= 0;
            rb2_wen <= 0;
            done    <= 0;
            bu_sel  <= mode;

            case (state)

            IDLE: if (start) begin
                len  <= mode ? 2 : (N >> 1);
                base <= 0;
                j    <= 0;
                zeta <= mode ? 7'd127 : 7'd0;
                state <= ISSUE;
            end

            ISSUE: begin
                rb1_raddr <= base + j;
                rb2_raddr <= base + j + len;
                rb3_raddr <= zeta;
                wait_cnt  <= 0;
                state     <= WAIT;
            end

            WAIT: begin
                if (wait_cnt == PIPE_LAT-1)
                    state <= WRITE;
                else
                    wait_cnt <= wait_cnt + 1;
            end

            WRITE: begin
                rb1_waddr <= base + j;
                rb2_waddr <= base + j + len;
                rb1_wen   <= 1;
                rb2_wen   <= 1;
                state     <= NEXT;
            end

            NEXT: begin
                if (j == len-1) begin
                    j <= 0;
                    base <= base + (len << 1);
                    if (base + (len << 1) >= N) begin
                        base <= 0;
                        if ((!mode && len == 2) ||
                            ( mode && len == (N>>1))) begin
                            drain_cnt <= 0;
                            state <= DRAIN;
                        end else begin
                            len <= mode ? (len << 1) : (len >> 1);
                            state <= ISSUE;
                        end
                    end else
                        state <= ISSUE;
                end else begin
                    j <= j + 1;
                    state <= ISSUE;
                end
            end

            DRAIN: begin
                if (drain_cnt < PIPE_LAT) begin
                    drain_cnt <= drain_cnt + 1;
                    rb1_wen <= 1;
                    rb2_wen <= 1;
                end else
                    state <= FINISH;
            end

            FINISH: done <= 1;

            endcase
        end
    end
endmodule
////////////
//mainnnnn
`timescale 1ns/1ps
module cu_fsm_pipe_safe #(
    parameter int N        = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,          // 0 = forward CT, 1 = inverse GS

    output logic [7:0] rb1_raddr,
    output logic [7:0] rb2_raddr,
    output logic [7:0] rb1_waddr,
    output logic [7:0] rb2_waddr,
    output logic [6:0] rb3_raddr,
    output logic       rb1_wen,
    output logic       rb2_wen,
    output logic       bu_sel,
    output logic       done
);

    typedef enum logic [2:0] {
        IDLE, ISSUE, WAIT, WRITE, NEXT, DRAIN, FINISH
    } state_t;

    state_t state_r, state_n;

    int len_r,  len_n;
    int base_r, base_n;
    int j_r,    j_n;
    int wait_cnt_r,  wait_cnt_n;
    int drain_cnt_r, drain_cnt_n;

    logic [6:0] zeta_r, zeta_n;

    logic [7:0] rb1_raddr_r, rb2_raddr_r;

    assign rb1_raddr = rb1_raddr_r;
    assign rb2_raddr = rb2_raddr_r;

    // =====================================================
    // Sequential
    // =====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r     <= IDLE;
            len_r       <= 0;
            base_r      <= 0;
            j_r         <= 0;
            zeta_r      <= 0;
            wait_cnt_r  <= 0;
            drain_cnt_r <= 0;
            rb1_raddr_r <= 0;
            rb2_raddr_r <= 0;
        end else begin
            state_r     <= state_n;
            len_r       <= len_n;
            base_r      <= base_n;
            j_r         <= j_n;
            zeta_r      <= zeta_n;
            wait_cnt_r  <= wait_cnt_n;
            drain_cnt_r <= drain_cnt_n;

            if (state_r == ISSUE) begin
                rb1_raddr_r <= base_r + j_r;
                rb2_raddr_r <= base_r + j_r + len_r;
                $display("FSM ISSUE @%0t | len=%0d base=%0d j=%0d | rb1_r=%0d rb2_r=%0d",
         $time, len_r, base_r, j_r,
         base_r + j_r,
         base_r + j_r + len_r);

            end
        end
    end

    // =====================================================
    // Combinational
    // =====================================================
    always_comb begin
        state_n     = state_r;
        len_n       = len_r;
        base_n      = base_r;
        j_n         = j_r;
        zeta_n      = zeta_r;
        wait_cnt_n  = wait_cnt_r;
        drain_cnt_n = drain_cnt_r;

        rb1_wen   = 0;
        rb2_wen   = 0;
        rb1_waddr = '0;
        rb2_waddr = '0;
        rb3_raddr = zeta_r;
        bu_sel    = mode;
        done      = 0;

        case (state_r)

        IDLE: begin
            if (start) begin
                len_n  = mode ? 2 : (N >> 1);
                base_n = 0;
                j_n    = 0;
                zeta_n = mode ? 7'd127 : 7'd0;
                state_n = ISSUE;
            end
        end

        ISSUE: begin
            wait_cnt_n = 0;
            state_n    = WAIT;
        end

        WAIT: begin
        $display("FSM WAIT  @%0t | cnt=%0d | HOLD rb1_r=%0d rb2_r=%0d",
             $time, wait_cnt_r,
             rb1_raddr_r, rb2_raddr_r);

            if (wait_cnt_r == PIPE_LAT + 1)
                state_n = WRITE;
            else
                wait_cnt_n = wait_cnt_r + 1;
        end

        WRITE: begin
         $display("FSM WRITE @%0t | W1=%0d W2=%0d | from rb1_r=%0d rb2_r=%0d",
             $time,
             base_r + j_r,
             base_r + j_r + len_r,
             rb1_raddr_r,
             rb2_raddr_r);
            rb1_waddr = base_r + j_r;
            rb2_waddr = base_r + j_r + len_r;
            rb1_wen   = 1;
            rb2_wen   = 1;
            state_n   = NEXT;
        end

        NEXT: begin
            if (j_r == len_r - 1) begin
                j_n    = 0;
                base_n = base_r + (len_r << 1);
                zeta_n = mode ? (zeta_r - 1) : (zeta_r + 1);

                if (base_r + (len_r << 1) >= N) begin
                    base_n = 0;
                    if ((!mode && len_r == 2) ||
                        ( mode && len_r == (N >> 1))) begin
                        drain_cnt_n = 0;
                        state_n     = DRAIN;
                    end else begin
                        len_n   = mode ? (len_r << 1) : (len_r >> 1);
                        state_n = ISSUE;
                    end
                end else begin
                    state_n = ISSUE;
                end
            end else begin
                j_n     = j_r + 1;
                state_n = ISSUE;
            end
        end

        DRAIN: begin
            if (drain_cnt_r < PIPE_LAT)
                drain_cnt_n = drain_cnt_r + 1;
            else
                state_n = FINISH;
        end

        FINISH: begin
            done    = 1;
            state_n = IDLE;
        end

        endcase
    end
endmodule


///////////
module cu_fsm_pipe_safe #(
    parameter int N = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,      // 0 = forward, 1 = inverse

    // -------- READ PORTS --------
    output logic        rd_bank_a,
    output logic [6:0]  rd_addr_a,
    output logic        rd_bank_b,
    output logic [6:0]  rd_addr_b,

    // -------- WRITE PORTS --------
    output logic        wr_bank_a,
    output logic [6:0]  wr_addr_a,
    output logic        wr_bank_b,
    output logic [6:0]  wr_addr_b,
    output logic        wr_en,

    // -------- TWIDDLE --------
    output logic [6:0]  zeta_idx,

    // -------- CONTROL --------
    output logic        bu_sel,
    output logic        done
);

    typedef enum logic [2:0] {
        IDLE, ISSUE, WAIT, WRITE, NEXT, FINISH
    } state_t;

    state_t state;

    int len, base, j;
    int wait_cnt;
    logic [6:0] zeta;

    // ---------------- SEQUENTIAL ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            len   <= 0;
            base  <= 0;
            j     <= 0;
            zeta  <= 0;
            wait_cnt <= 0;
        end else begin
            case (state)

            IDLE: if (start) begin
                len  <= mode ? 2 : (N>>1);
                base <= 0;
                j    <= 0;
                zeta <= mode ? 7'd127 : 7'd0;
                state <= ISSUE;
            end

            ISSUE: begin
                wait_cnt <= 0;
                state <= WAIT;
            end

            WAIT: begin
                if (wait_cnt == PIPE_LAT-1)
                    state <= WRITE;
                else
                    wait_cnt <= wait_cnt + 1;
            end

            WRITE: state <= NEXT;

            NEXT: begin
                if (j == len-1) begin
                    j <= 0;
                    base <= base + (len<<1);

                    if (base + (len<<1) >= N) begin
                        base <= 0;
                        if ((!mode && len==2) ||
                            ( mode && len==(N>>1)))
                            state <= FINISH;
                        else begin
                            len <= mode ? (len<<1) : (len>>1);
                            zeta <= mode ? zeta-1 : zeta+1;
                            state <= ISSUE;
                        end
                    end else begin
                        zeta <= mode ? zeta-1 : zeta+1;
                        state <= ISSUE;
                    end
                end else begin
                    j <= j + 1;
                    state <= ISSUE;
                end
            end

            FINISH: state <= FINISH;

            endcase
        end
    end

    // ---------------- COMBINATIONAL ----------------
    always_comb begin
        done   = (state == FINISH);
        bu_sel = mode;
        wr_en  = (state == WRITE);

        // Banked addressing (even/odd)
        rd_bank_a = (base + j) & 1;
        rd_addr_a = (base + j) >> 1;

        rd_bank_b = (base + j + len) & 1;
        rd_addr_b = (base + j + len) >> 1;

        wr_bank_a = rd_bank_a;
        wr_addr_a = rd_addr_a;

        wr_bank_b = rd_bank_b;
        wr_addr_b = rd_addr_b;

        zeta_idx  = zeta;
    end

endmodule
*/
module cu_fsm_pipe_safe #(
    parameter int N        = 256,
    parameter int PIPE_LAT = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,          // 0 = forward (CT), 1 = inverse (GS)

    output logic [7:0] rb1_raddr,
    output logic [7:0] rb2_raddr,
    output logic [7:0] rb1_waddr,
    output logic [7:0] rb2_waddr,
    output logic [6:0] rb3_raddr,
    output logic       rb1_wen,
    output logic       rb2_wen,
    output logic       bu_sel,
    output logic       done
);

    typedef enum logic [2:0] {
        IDLE, ISSUE, WAIT, WRITE, NEXT, DRAIN, FINISH
    } state_t;

    // -------- REGISTERED STATE --------
    state_t state_r, state_n;

    int len_r, len_n;
    int base_r, base_n;
    int j_r, j_n;
    int wait_cnt_r, wait_cnt_n;
    int drain_cnt_r, drain_cnt_n;
    logic [6:0] zeta_r, zeta_n;

    // ================= SEQUENTIAL =================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r     <= IDLE;
            len_r       <= 0;
            base_r      <= 0;
            j_r         <= 0;
            zeta_r      <= 0;
            wait_cnt_r  <= 0;
            drain_cnt_r <= 0;
        end else begin
            state_r     <= state_n;
            len_r       <= len_n;
            base_r      <= base_n;
            j_r         <= j_n;
            zeta_r      <= zeta_n;
            wait_cnt_r  <= wait_cnt_n;
            drain_cnt_r <= drain_cnt_n;
        end
    end

    // ================= COMBINATIONAL =================
    always_comb begin
    // defaults
    state_n     = state_r;
    len_n       = len_r;
    base_n      = base_r;
    j_n         = j_r;
    zeta_n      = zeta_r;
    wait_cnt_n  = wait_cnt_r;
    drain_cnt_n = drain_cnt_r;

    rb1_wen = 0;
    rb2_wen = 0;
    done    = 0;
    bu_sel  = mode;

    rb1_raddr = '0;
    rb2_raddr = '0;
    rb1_waddr = '0;
    rb2_waddr = '0;
    rb3_raddr = zeta_r;

    case (state_r)

    IDLE: begin
        if (start) begin
            len_n   = mode ? 2 : (N >> 1);
            base_n  = 0;
            j_n     = 0;
            zeta_n  = mode ? 7'd127 : 7'd0;
            state_n = ISSUE;
        end
    end

    ISSUE: begin
        rb1_raddr = base_r + j_r;
        rb2_raddr = base_r + j_r + len_r;
        wait_cnt_n = 0;
        state_n = WAIT;
    end

    WAIT: begin
        if (wait_cnt_r == PIPE_LAT+2)
            state_n = WRITE;
        else
            wait_cnt_n = wait_cnt_r + 1;
    end

    WRITE: begin
        rb1_waddr = base_r + j_r;
        rb2_waddr = base_r + j_r + len_r;
        rb1_wen = 1;
        rb2_wen = 1;
        state_n = NEXT;
    end

    NEXT: begin
        if (j_r == len_r - 1) begin
            j_n    = 0;
            base_n = base_r + (len_r << 1);
            zeta_n = mode ? (zeta_r - 1) : (zeta_r + 1);

            if (base_n >= N) begin
                base_n = 0;
                if ((!mode && len_r == 2) ||
                    ( mode && len_r == (N >> 1))) begin
                    drain_cnt_n = 0;
                    state_n = DRAIN;
                end else begin
                    len_n = mode ? (len_r << 1) : (len_r >> 1);
                    state_n = ISSUE;
                end
            end else begin
                state_n = ISSUE;
            end
        end else begin
            j_n = j_r + 1;
            state_n = ISSUE;
            $display("FSM: len_n=%0d base=%0d j=%0d rb1_r=%0d rb2_r=%0d",
         len_n, start, j_n, rb1_raddr, rb2_raddr);

        end
    end

    DRAIN: begin
        if (drain_cnt_r < PIPE_LAT)
            drain_cnt_n = drain_cnt_r + 1;
        else
            state_n = FINISH;
    end

    FINISH: begin
        done = 1;
        rb1_wen = 1'b0;
    rb2_wen = 1'b0;
    end
    endcase
end


endmodule   
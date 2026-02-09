/*module unif_ntt_top_pipe #(
    parameter int N     = 256,
    parameter int Q     = 3329,
    parameter int INV_N = 3303
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         start,
    input  logic         mode,          // 0 = forward, 1 = inverse

    input  logic [15:0]  host_in_data,
    input  logic         host_in_valid,

    output logic [15:0]  out_data,
    output logic         out_valid,
    output logic         done
);

    // =====================================================
    // Control Unit
    // =====================================================
    logic        load_input_en;
    logic [7:0]  load_input_addr;

    logic [7:0]  rb1_raddr, rb2_raddr;
    logic [6:0]  rb3_raddr;

    logic [7:0]  rb1_waddr, rb2_waddr;
    logic        rb1_wen, rb2_wen;
    logic        bu_sel;

    cu_fsm_pipe cu (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode(mode),

        .load_input_en(load_input_en),
        .load_input_addr(load_input_addr),

        .load_twiddle_en(),        // not used (ROM)
        .load_twiddle_addr(),

        .rb1_raddr(rb1_raddr),
        .rb2_raddr(rb2_raddr),
        .rb3_raddr(rb3_raddr),

        .rb1_waddr(rb1_waddr),
        .rb2_waddr(rb2_waddr),
        .rb1_wen(rb1_wen),
        .rb2_wen(rb2_wen),

        .bu_sel(bu_sel),
        .done(done)
    );

    // =====================================================
    // ZETA ROM (NO I/O PORTS!)
    // =====================================================
    logic [15:0] zeta_rom [0:127];
    logic [15:0] rb3_q;

    initial begin
       // $readmemh("C:/Users/PC/Downloads/kyber_zetas.mem", zeta_rom);
       $readmemh("C:/Users/Lenovo/Downloads/kyber_zetas.mem", zeta_rom);
    end

    assign rb3_q = zeta_rom[rb3_raddr];

    // =====================================================
    // Register Banks
    // =====================================================
    logic [15:0] rb1_q, rb2_q;
    logic [15:0] A_out, B_out;

    // RB1 read mux (compute vs output)
    logic        out_reading;
    logic [7:0]  out_rd_addr;
    logic [7:0]  rb1_addr;

    assign rb1_addr = out_reading ? out_rd_addr : rb1_raddr;

    // write arbitration (input load has priority)
    logic        rb1_wen_i, rb2_wen_i;
    logic [7:0]  rb1_waddr_i, rb2_waddr_i;
    logic [15:0] rb1_wdata_i, rb2_wdata_i;

    always_comb begin
        // defaults = butterfly
        rb1_wen_i   = rb1_wen;
        rb1_waddr_i = rb1_waddr;
        rb1_wdata_i = A_out;

        rb2_wen_i   = rb2_wen;
        rb2_waddr_i = rb2_waddr;
        rb2_wdata_i = B_out;

        // override during input load
        if (load_input_en && host_in_valid) begin
            rb1_wen_i   = 1'b1;
            rb1_waddr_i = load_input_addr;
            rb1_wdata_i = host_in_data;

            rb2_wen_i   = 1'b1;
            rb2_waddr_i = load_input_addr;
            rb2_wdata_i = host_in_data;
        end
    end

    regbank #(.DEPTH(256)) RB1 (
        .clk(clk),
      //  .rst_n(rst_n),
        .wen(rb1_wen_i),
        .waddr(rb1_waddr_i),
        .wdata(rb1_wdata_i),
        .raddr(rb1_addr),
        .rdata(rb1_q)
    );

    regbank #(.DEPTH(256)) RB2 (
        .clk(clk),
       // .rst_n(rst_n),
        .wen(rb2_wen_i),
        .waddr(rb2_waddr_i),
        .wdata(rb2_wdata_i),
        .raddr(rb2_raddr),
        .rdata(rb2_q)
    );

    // =====================================================
    // Butterfly Unit (CT / GS unified)
    // =====================================================
    unif_bu_pipe bu (
        .clk(clk),
        .rst_n(rst_n),
        .a(rb1_q),
        .b(rb2_q),
        .w(rb3_q),
        .sel(bu_sel),
        .A_out(A_out),
        .B_out(B_out)
    );

    // =====================================================
    // OUTPUT FSM (256 samples)
    // =====================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reading <= 0;
            out_rd_addr <= 0;
            out_valid   <= 0;
            out_data    <= 0;
        end else begin
            if (done && !out_reading) begin
                out_reading <= 1;
                out_rd_addr <= 0;
                out_valid   <= 0;
            end
            else if (out_reading) begin
                out_data  <= rb1_q;
                out_valid <= 1;

                if (out_rd_addr == 8'd255) begin
                    out_reading <= 0;
                    out_valid   <= 0;
                end else
                    out_rd_addr <= out_rd_addr + 1;
            end else
                out_valid <= 0;
        end
    end

endmodule

/////////
`timescale 1ns/1ps

module unif_ntt_top_pipe (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        mode,          // 0 = forward, 1 = inverse

    input  logic [15:0] host_in_data,
    input  logic        host_in_valid,

    output logic [15:0] out_data,
    output logic        out_valid,
    output logic        done
);

    localparam int N = 256;

    // =====================================================
    // FSM signals
    // =====================================================
    logic [7:0] base, j, len;
    logic [6:0] zeta_idx;
    logic       wen, bu_sel;

    cu_fsm_pipe_safe FSM (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .mode   (mode),
        .base   (base),
        .j      (j),
        .len    (len),
        .zeta   (zeta_idx),
        .bu_sel (bu_sel),
        .wen    (wen),
        .done   (done)
    );

    // =====================================================
    // Zeta ROM (Kyber Appendix-A)
    // =====================================================
    logic [15:0] zeta_rom [0:127];

    initial begin
        $readmemh("C:/Users/Lenovo/Downloads/kyber_zetas.mem", zeta_rom);
    end

    wire [15:0] w = zeta_rom[zeta_idx];

    // =====================================================
    // INPUT LOAD ADDRESS COUNTER  (CRITICAL)
    // =====================================================
    logic [7:0] load_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_addr <= 0;
        else if (host_in_valid)
            load_addr <= load_addr + 1'b1;
        else
            load_addr <= 0;
    end

    // =====================================================
    // REGISTER BANKS
    // =====================================================
    logic [15:0] rb1_q, rb2_q;
    logic [15:0] A_out, B_out;

    // Read addresses
    wire [7:0] rd_a = base + j;
    wire [7:0] rd_b = base + j + len;

    // Write addresses (same as read for in-place NTT)
    wire [7:0] wr_a = base + j;
    wire [7:0] wr_b = base + j + len;

    // =====================================================
    // WRITE ARBITRATION  (THIS FIXES ALL X's)
    // =====================================================
    logic        rb1_wen_i, rb2_wen_i;
    logic [7:0]  rb1_waddr_i, rb2_waddr_i;
    logic [15:0] rb1_wdata_i, rb2_wdata_i;

    always_comb begin
        // defaults = butterfly writeback
        rb1_wen_i   = wen;
        rb1_waddr_i = wr_a;
        rb1_wdata_i = A_out;

        rb2_wen_i   = wen;
        rb2_waddr_i = wr_b;
        rb2_wdata_i = B_out;

        // input loading has priority
        if (host_in_valid) begin
            rb1_wen_i   = 1'b1;
            rb1_waddr_i = load_addr;
            rb1_wdata_i = host_in_data;

            rb2_wen_i   = 1'b1;
            rb2_waddr_i = load_addr;
            rb2_wdata_i = 16'd0;   // RB2 MUST START AS ZERO
        end
    end

    // =====================================================
    // RB1
    // =====================================================
    regbank #(.WIDTH(16), .DEPTH(256)) RB1 (
        .clk   (clk),
        .wen   (rb1_wen_i),
        .waddr (rb1_waddr_i),
        .wdata (rb1_wdata_i),
        .raddr (rd_a),
        .rdata (rb1_q)
    );

    // =====================================================
    // RB2
    // =====================================================
    regbank #(.WIDTH(16), .DEPTH(256)) RB2 (
        .clk   (clk),
        .wen   (rb2_wen_i),
        .waddr (rb2_waddr_i),
        .wdata (rb2_wdata_i),
        .raddr (rd_b),
        .rdata (rb2_q)
    );

    // =====================================================
    // BUTTERFLY UNIT (yours, unchanged)
    // =====================================================
    unif_bu_pipe BU (
        .clk   (clk),
        .rst_n (rst_n),
        .sel   (bu_sel),
        .a     (rb1_q),
        .b     (rb2_q),
        .w     (w),
        .A_out (A_out),
        .B_out (B_out)
    );

    // =====================================================
    // OUTPUT STREAMING
    // =====================================================
    logic [7:0] out_addr;
    logic       reading;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reading   <= 0;
            out_addr  <= 0;
            out_valid <= 0;
            out_data  <= 0;
        end else begin
            if (done && !reading) begin
                reading  <= 1;
                out_addr <= 0;
                out_valid <= 0;
            end
            else if (reading) begin
                out_data  <= rb1_q;
                out_valid <= 1;

                if (out_addr == 8'd255) begin
                    reading   <= 0;
                    out_valid <= 0;
                end else
                    out_addr <= out_addr + 1'b1;
            end else
                out_valid <= 0;
        end
    end

endmodule
1/5
///////////
27/1 main

`timescale 1ns/1ps

module unif_ntt_top_pipe #(
    parameter int N     = 256,
    parameter int WIDTH = 16,
    parameter int PIPE_LAT = 3
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start,
    input  logic              mode,          // 0 = forward, 1 = inverse

    input  logic [WIDTH-1:0]  host_in_data,
    input  logic              host_in_valid,

    output logic [WIDTH-1:0]  out_data,
    output logic              out_valid,
    output logic              done
);

    // =====================================================
    // FSM <-> Datapath signals
    // =====================================================
    logic [7:0] rb1_raddr_fsm, rb2_raddr;
    logic [7:0] rb1_waddr, rb2_waddr;
    logic [6:0] rb3_raddr;
    logic       rb1_wen, rb2_wen;
    logic       bu_sel;
// =====================================================
// PIPELINE ALIGNMENT FOR WRITE ADDRESSES (CRITICAL FIX)
// =====================================================
logic [7:0] rb1_waddr_d [0:PIPE_LAT];
logic [7:0] rb2_waddr_d [0:PIPE_LAT];
logic       rb1_wen_d   [0:PIPE_LAT];
logic       rb2_wen_d   [0:PIPE_LAT];
logic [7:0] rb1_raddr_mux;

    // =====================================================
    // SAFE FSM (pipeline aware)
    // =====================================================
    cu_fsm_pipe_safe CU (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mode(mode),

    .rb1_raddr(rb1_raddr_fsm),
    .rb2_raddr(rb2_raddr),
    .rb1_waddr(rb1_waddr),
    .rb2_waddr(rb2_waddr),
    .rb3_raddr(rb3_raddr),
    .rb1_wen(rb1_wen),
    .rb2_wen(rb2_wen),

    .bu_sel(bu_sel),
    .done(done)
);


integer p;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (p = 0; p <= PIPE_LAT; p = p + 1) begin
            rb1_waddr_d[p] <= 0;
            rb2_waddr_d[p] <= 0;
            rb1_wen_d[p]   <= 0;
            rb2_wen_d[p]   <= 0;
        end
    end else begin
        // stage 0 = FSM outputs
        rb1_waddr_d[0] <= rb1_waddr;
        rb2_waddr_d[0] <= rb2_waddr;
        rb1_wen_d[0]   <= rb1_wen;
        rb2_wen_d[0]   <= rb2_wen;

        // shift pipeline
        for (p = 1; p <= PIPE_LAT; p = p + 1) begin
            rb1_waddr_d[p] <= rb1_waddr_d[p-1];
            rb2_waddr_d[p] <= rb2_waddr_d[p-1];
            rb1_wen_d[p]   <= rb1_wen_d[p-1];
            rb2_wen_d[p]   <= rb2_wen_d[p-1];
        end
    end
end

    // =====================================================
    // ZETA ROM (synth-safe)
    // =====================================================
    logic [WIDTH-1:0] zeta_rom [0:127];
    logic [WIDTH-1:0] zeta_q;

    initial begin
        $readmemh("C:/Users/Lenovo/Downloads/kyber_zetas.mem", zeta_rom);
    end

    assign zeta_q = zeta_rom[rb3_raddr];

    // =====================================================
    // INPUT LOAD ADDRESS COUNTER (TOP-LEVEL)
    // =====================================================
    logic [7:0] load_input_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_input_addr <= 8'd0;
        else if (host_in_valid)
            load_input_addr <= load_input_addr + 1'b1;
         else
   load_input_addr <= 8'd0;
    end
////
logic compute_active;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        compute_active <= 1'b0;
    else if (start)
        compute_active <= 1'b1;
    else if (done)
        compute_active <= 1'b0;
end

    // =====================================================
    // REGISTER BANKS
    // =====================================================
    logic [WIDTH-1:0] rb1_q, rb2_q;
    logic [WIDTH-1:0] A_out, B_out;

    // Output read mux
    logic reading;
    logic [7:0] out_addr;
   // logic [7:0] rb1_raddr;

   // assign rb1_raddr = reading ? out_addr : rb1_raddr_fsm;

    // Write arbitration (SYNTH SAFE)
    logic        rb1_wen_i, rb2_wen_i;
    logic [7:0]  rb1_waddr_i, rb2_waddr_i;
    logic [WIDTH-1:0] rb1_wdata_i, rb2_wdata_i;

    always_comb begin
    // ---------------- defaults (NTT writes) ----------------
    rb1_wen_i   = rb1_wen_d[PIPE_LAT];
    rb1_waddr_i = rb1_waddr_d[PIPE_LAT];
    rb1_wdata_i = A_out;

    rb2_wen_i   = rb2_wen_d[PIPE_LAT];
    rb2_waddr_i = rb2_waddr_d[PIPE_LAT];
    rb2_wdata_i = B_out;

    // ---------------- input load ONLY when NOT computing ----------------
    if (!compute_active && host_in_valid) begin
        rb1_wen_i   = 1'b1;
        rb1_waddr_i = load_input_addr;
        rb1_wdata_i = host_in_data;

        // ---------- RB2 ONLY for upper half ----------
    if (load_input_addr >= 128) begin
        rb2_wen_i   = 1'b1;
        rb2_waddr_i = load_input_addr - 128;
        rb2_wdata_i = host_in_data;
    end else begin
        rb2_wen_i = 1'b0;
    end // OR 0 if your paper wants
    end
end

      // -------- CRITICAL FIX --------
    // Once computation starts, NEVER allow host to touch RB2
//    if (start) begin
//        rb2_wen_i = rb2_wen_d[PIPE_LAT];  // only butterfly may write RB2
//    end
//end


    // RB1
    regbank #(.WIDTH(WIDTH), .DEPTH(256)) RB1 (
        .clk   (clk),
      .rst_n (rst_n),
        .wen   (rb1_wen_i),
        .waddr (rb1_waddr_i),
        .wdata (rb1_wdata_i),
        .raddr (rb1_raddr_mux),
        .rdata (rb1_q)
    );

    // RB2
    regbank #(.WIDTH(WIDTH), .DEPTH(256)) RB2 (
        .clk   (clk),
         .rst_n (rst_n),
        .wen   (rb2_wen_i),
        .waddr (rb2_waddr_i),
        .wdata (rb2_wdata_i),
        .raddr (rb2_raddr),
        .rdata (rb2_q)
    );

    // =====================================================
    // BUTTERFLY UNIT (Barrett based)
    // =====================================================
    unif_bu_pipe BU (
        .clk   (clk),
        .rst_n (rst_n),
        .sel   (bu_sel),
        .a     (rb1_q),
        .b     (rb2_q),
        .w     (zeta_q),
        .A_out (A_out),
        .B_out (B_out)
    );

    // =====================================================
    // OUTPUT STREAMING (1-cycle safe)
    // =====================================================
logic [7:0] out_addr_r;

logic [15:0] rb1_q_d;   // delayed read

// delay register for RAM output
always_ff @(posedge clk) begin
    rb1_q_d <= rb1_q;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reading    <= 0;
        out_addr_r <= 0;
        out_valid  <= 0;
        out_data   <= 0;
    end else begin
        if (done && !reading) begin
            reading    <= 1;
            out_addr_r <= 0;
            out_valid  <= 0;
        end
        else if (reading) begin
            out_data  <= rb1_q_d;   // data from previous addr
            out_valid <= 1;

            if (out_addr_r == 8'd255) begin
                reading   <= 0;
                out_valid <= 0;
            end else begin
                out_addr_r <= out_addr_r + 1;
            end
        end else begin
            out_valid <= 0;
        end
    end
end
always_ff @(posedge clk) begin
        if (start) begin
            $display("START @%0t | RB1[0]=%0d RB2[128]=%0d",
                     $time,
                     RB1.mem[0],
                     RB2.mem[128]);
              
 
        $display("START | RB1[0]=%0d RB2[0]=%0d",
                 RB1.mem[0], RB2.mem[0]);


        end
    end
//assign rb1_raddr = reading ? out_addr_r : rb1_raddr_fsm;
always_comb begin
    if (reading)
        rb1_raddr_mux = out_addr_r;
    else if (!done)
        rb1_raddr_mux = rb1_raddr_fsm;
    else
        rb1_raddr_mux = 8'd0;
end


endmodule

/////////////////////
module unif_ntt_top_pipe #(
    parameter int N = 256,
    parameter int WIDTH = 16
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic mode,

    input  logic [WIDTH-1:0] host_in_data,
    input  logic host_in_valid,

    output logic [WIDTH-1:0] out_data,
    output logic out_valid,
    output logic done
);

    // FSM → memory
    logic rd_bank_a, rd_bank_b;
    logic [6:0] rd_addr_a, rd_addr_b;
    logic wr_bank_a, wr_bank_b;
    logic [6:0] wr_addr_a, wr_addr_b;
    logic wr_en;
    logic [6:0] zeta_idx;
    logic bu_sel;

    cu_fsm_pipe_safe CU (
        .clk(clk), .rst_n(rst_n), .start(start), .mode(mode),
        .rd_bank_a(rd_bank_a), .rd_addr_a(rd_addr_a),
        .rd_bank_b(rd_bank_b), .rd_addr_b(rd_addr_b),
        .wr_bank_a(wr_bank_a), .wr_addr_a(wr_addr_a),
        .wr_bank_b(wr_bank_b), .wr_addr_b(wr_addr_b),
        .wr_en(wr_en),
        .zeta_idx(zeta_idx),
        .bu_sel(bu_sel),
        .done(done)
    );

    // Zeta ROM (synth OK)
    logic [WIDTH-1:0] zeta_rom [0:127];
    logic [WIDTH-1:0] zeta_q;
    initial $readmemh("C:/Users/Lenovo/Downloads/kyber_zetas.mem", zeta_rom);
    assign zeta_q = zeta_rom[zeta_idx];

    // Banks
    logic [WIDTH-1:0] bank0_q, bank1_q;
    logic [WIDTH-1:0] bank0_qb, bank1_qb;

    regbank BANK0 (.clk(clk),
        .wen(wr_en && !wr_bank_a), .waddr(wr_addr_a), .wdata(A_out),
        .raddr(rd_addr_a), .rdata(bank0_q));

    regbank BANK1 (.clk(clk),
        .wen(wr_en &&  wr_bank_a), .waddr(wr_addr_a), .wdata(A_out),
        .raddr(rd_addr_a), .rdata(bank1_q));

    regbank BANK0B (.clk(clk),
        .wen(wr_en && !wr_bank_b), .waddr(wr_addr_b), .wdata(B_out),
        .raddr(rd_addr_b), .rdata(bank0_qb));

    regbank BANK1B (.clk(clk),
        .wen(wr_en &&  wr_bank_b), .waddr(wr_addr_b), .wdata(B_out),
        .raddr(rd_addr_b), .rdata(bank1_qb));

    // Read mux
    logic [WIDTH-1:0] a_in, b_in;
    assign a_in = rd_bank_a ? bank1_q  : bank0_q;
    assign b_in = rd_bank_b ? bank1_qb : bank0_qb;

    // BU (UNCHANGED - yours is correct)
    logic [WIDTH-1:0] A_out, B_out;
    unif_bu_pipe BU (
        .clk(clk), .rst_n(rst_n),
        .sel(bu_sel), .a(a_in), .b(b_in), .w(zeta_q),
        .A_out(A_out), .B_out(B_out)
    );

    // Output (natural order)
    logic [7:0] out_idx;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_idx <= 0; out_valid <= 0;
        end else if (done) begin
            out_valid <= 1;
            out_data  <= out_idx[0] ? bank1_q : bank0_q;
            out_idx   <= out_idx + 1;
        end else
            out_valid <= 0;
    end
endmodule
/////////
`timescale 1ns/1ps
module unif_ntt_top_pipe #(
    parameter int N        = 256,
    parameter int WIDTH    = 16,
    parameter int PIPE_LAT = 3
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start,
    input  logic              mode,          // 0 = forward, 1 = inverse

    input  logic [WIDTH-1:0]  host_in_data,
    input  logic              host_in_valid,

    output logic [WIDTH-1:0]  out_data,
    output logic              out_valid,
    output logic              done
);

    // =====================================================
    // FSM <-> TOP signals
    // =====================================================
    logic [7:0] rb1_raddr, rb2_raddr;
    logic [7:0] rb1_waddr, rb2_waddr;
    logic [6:0] rb3_raddr;
    logic       rb1_wen, rb2_wen;
    logic       bu_sel;

    cu_fsm_pipe_safe #(
        .N(N),
        .PIPE_LAT(PIPE_LAT)
    ) CU (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mode(mode),

        .rb1_raddr(rb1_raddr),
        .rb2_raddr(rb2_raddr),
        .rb1_waddr(rb1_waddr),
        .rb2_waddr(rb2_waddr),
        .rb3_raddr(rb3_raddr),
        .rb1_wen(rb1_wen),
        .rb2_wen(rb2_wen),

        .bu_sel(bu_sel),
        .done(done)
    );

    // =====================================================
    // SINGLE POLYNOMIAL MEMORY (THE FIX)
    // =====================================================
    logic [WIDTH-1:0] poly_mem [0:N-1];

    logic [WIDTH-1:0] a_q, b_q;

    // Read (1-cycle latency RAM model)
    always_ff @(posedge clk) begin
        a_q <= poly_mem[rb1_raddr];
        b_q <= poly_mem[rb2_raddr];
    end

    // =====================================================
    // ZETA ROM
    // =====================================================
    logic [WIDTH-1:0] zeta_rom [0:127];
    logic [WIDTH-1:0] zeta_q;

    initial begin
        $readmemh("kyber_zetas.mem", zeta_rom);
    end

    assign zeta_q = zeta_rom[rb3_raddr];

    // =====================================================
    // BUTTERFLY UNIT
    // =====================================================
    logic [WIDTH-1:0] A_out, B_out;

    unif_bu_pipe BU (
        .clk   (clk),
        .rst_n (rst_n),
        .sel   (bu_sel),
        .a     (a_q),
        .b     (b_q),
        .w     (zeta_q),
        .A_out (A_out),
        .B_out (B_out)
    );

    // =====================================================
    // PIPELINE ALIGNMENT FOR WRITES
    // =====================================================
    logic [7:0] waddr_a_d [0:PIPE_LAT];
    logic [7:0] waddr_b_d [0:PIPE_LAT];
    logic       wen_d     [0:PIPE_LAT];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i <= PIPE_LAT; i++) begin
                waddr_a_d[i] <= 0;
                waddr_b_d[i] <= 0;
                wen_d[i]     <= 0;
            end
        end else begin
            waddr_a_d[0] <= rb1_waddr;
            waddr_b_d[0] <= rb2_waddr;
            wen_d[0]     <= rb1_wen;

            for (i = 1; i <= PIPE_LAT; i++) begin
                waddr_a_d[i] <= waddr_a_d[i-1];
                waddr_b_d[i] <= waddr_b_d[i-1];
                wen_d[i]     <= wen_d[i-1];
            end
        end
    end

    // =====================================================
    // WRITE BACK (HOST OR BUTTERFLY)
    // =====================================================
    logic [7:0] load_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_addr <= 0;
        else if (host_in_valid)
            load_addr <= load_addr + 1;
        else
            load_addr <= 0;
    end

    always_ff @(posedge clk) begin
        if (host_in_valid) begin
            poly_mem[load_addr] <= host_in_data;
        end
        else if (wen_d[PIPE_LAT]) begin
            poly_mem[waddr_a_d[PIPE_LAT]] <= A_out;
            poly_mem[waddr_b_d[PIPE_LAT]] <= B_out;
        end
    end

    // =====================================================
    // OUTPUT STREAMING
    // =====================================================
    logic [7:0] out_addr;
    logic [WIDTH-1:0] out_q;
    logic reading;

    always_ff @(posedge clk) begin
        out_q <= poly_mem[out_addr];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reading   <= 0;
            out_addr  <= 0;
            out_valid <= 0;
            out_data  <= 0;
        end else begin
            if (done && !reading) begin
                reading   <= 1;
                out_addr  <= 0;
                out_valid <= 0;
            end
            else if (reading) begin
                out_data  <= out_q;
                out_valid <= 1;

                if (out_addr == N-1) begin
                    reading   <= 0;
                    out_valid <= 0;
                end else begin
                    out_addr <= out_addr + 1;
                end
            end else begin
                out_valid <= 0;
            end
        end
    end

endmodule
*/

module unif_ntt_top_pipe #(
    parameter int N     = 256,
    parameter int WIDTH = 16,
    parameter int PIPE_LAT = 3
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              start,
    input  logic              mode,          // 0 = forward, 1 = inverse

    input  logic [WIDTH-1:0]  host_in_data,
    input  logic              host_in_valid,

    output logic [WIDTH-1:0]  out_data,
    output logic              out_valid,
    output logic              done
);

    // =====================================================
    // FSM <-> Datapath signals
    // =====================================================
    logic [7:0] rb1_raddr_fsm, rb2_raddr;
    logic [7:0] rb1_waddr, rb2_waddr;
    logic [6:0] rb3_raddr;
    logic       rb1_wen, rb2_wen;
    logic       bu_sel;
// =====================================================
// PIPELINE ALIGNMENT FOR WRITE ADDRESSES (CRITICAL FIX)
// =====================================================
logic [7:0] rb1_waddr_d [0:PIPE_LAT];
logic [7:0] rb2_waddr_d [0:PIPE_LAT];
logic       rb1_wen_d   [0:PIPE_LAT];
logic       rb2_wen_d   [0:PIPE_LAT];
logic [7:0] rb1_raddr_mux;

    // =====================================================
    // SAFE FSM (pipeline aware)
    // =====================================================
    cu_fsm_pipe_safe CU (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mode(mode),

    .rb1_raddr(rb1_raddr_fsm),
    .rb2_raddr(rb2_raddr),
    .rb1_waddr(rb1_waddr),
    .rb2_waddr(rb2_waddr),
    .rb3_raddr(rb3_raddr),
    .rb1_wen(rb1_wen),
    .rb2_wen(rb2_wen),

    .bu_sel(bu_sel),
    .done(done)
);


integer p;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (p = 0; p <= PIPE_LAT; p = p + 1) begin
            rb1_waddr_d[p] <= 0;
            rb2_waddr_d[p] <= 0;
            rb1_wen_d[p]   <= 0;
            rb2_wen_d[p]   <= 0;
        end
    end else begin
        // stage 0 = FSM outputs
        rb1_waddr_d[0] <= rb1_waddr;
        rb2_waddr_d[0] <= rb2_waddr;
        rb1_wen_d[0]   <= rb1_wen;
        rb2_wen_d[0]   <= rb2_wen;

        // shift pipeline
        for (p = 1; p <= PIPE_LAT; p = p + 1) begin
            rb1_waddr_d[p] <= rb1_waddr_d[p-1];
            rb2_waddr_d[p] <= rb2_waddr_d[p-1];
            rb1_wen_d[p]   <= rb1_wen_d[p-1];
            rb2_wen_d[p]   <= rb2_wen_d[p-1];
        end
    end
end

    // =====================================================
    // ZETA ROM (synth-safe)
    // =====================================================
    logic [WIDTH-1:0] zeta_rom [0:127];
    logic [WIDTH-1:0] zeta_q;

    initial begin
        $readmemh("C:/Users/Lenovo/Downloads/kyber_zetas.mem", zeta_rom);
    end

    assign zeta_q = zeta_rom[rb3_raddr];

    // =====================================================
    // INPUT LOAD ADDRESS COUNTER (TOP-LEVEL)
    // =====================================================
    logic [7:0] load_input_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_input_addr <= 8'd0;
        else if (host_in_valid)
            load_input_addr <= load_input_addr + 1'b1;
        else
            load_input_addr <= 8'd0;
    end

    // =====================================================
    // REGISTER BANKS
    // =====================================================
    logic [WIDTH-1:0] rb1_q, rb2_q;
    logic [WIDTH-1:0] A_out, B_out;

    // Output read mux
    logic reading;
    logic [7:0] out_addr;
   // logic [7:0] rb1_raddr;

   // assign rb1_raddr = reading ? out_addr : rb1_raddr_fsm;

    // Write arbitration (SYNTH SAFE)
    logic        rb1_wen_i, rb2_wen_i;
    logic [7:0]  rb1_waddr_i, rb2_waddr_i;
    logic [WIDTH-1:0] rb1_wdata_i, rb2_wdata_i;

    always_comb begin
        // defaults = butterfly writes
     //rb1_wen_i = (!host_in_valid) && rb1_wen_d[PIPE_LAT];
       rb1_wen_i   = rb1_wen_d[PIPE_LAT];
rb1_waddr_i = rb1_waddr_d[PIPE_LAT];
rb1_wdata_i = A_out;

//rb2_wen_i = (!host_in_valid) && rb2_wen_d[PIPE_LAT];
rb2_wen_i   = rb2_wen_d[PIPE_LAT];
rb2_waddr_i = rb2_waddr_d[PIPE_LAT];
rb2_wdata_i = B_out;


        // input load (TOP controlled)
        if (host_in_valid&&!start) begin
            rb1_wen_i   = 1'b1;
            rb1_waddr_i = load_input_addr;
            rb1_wdata_i = host_in_data;

rb2_wen_i   = 1'b1;
rb2_waddr_i = load_input_addr;
rb2_wdata_i = '0;

    end
end
    // RB1
    regbank #(.WIDTH(WIDTH), .DEPTH(256)) RB1 (
        .clk   (clk),
     
        .wen   (rb1_wen_i),
        .waddr (rb1_waddr_i),
        .wdata (rb1_wdata_i),
        .raddr (rb1_raddr_mux),
        .rdata (rb1_q)
    );

    // RB2
    regbank #(.WIDTH(WIDTH), .DEPTH(256)) RB2 (
        .clk   (clk),
        
        .wen   (rb2_wen_i),
        .waddr (rb2_waddr_i),
        .wdata (rb2_wdata_i),
        .raddr (rb2_raddr),
        .rdata (rb2_q)
    );

    // =====================================================
    // BUTTERFLY UNIT (Barrett based)
    // =====================================================
    unif_bu_pipe BU (
        .clk   (clk),
        .rst_n (rst_n),
        .sel   (bu_sel),
        .a     (rb1_q),
        .b     (rb2_q),
        .w     (zeta_q),
        .A_out (A_out),
        .B_out (B_out)
    );

    // =====================================================
    // OUTPUT STREAMING (1-cycle safe)
    // =====================================================
logic [7:0] out_addr_r;

logic [15:0] rb1_q_d;   // delayed read

// delay register for RAM output
always_ff @(posedge clk) begin
    rb1_q_d <= rb1_q;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reading    <= 0;
        out_addr_r <= 0;
        out_valid  <= 0;
        out_data   <= 0;
    end else begin
        if (done && !reading) begin
            reading    <= 1;
            out_addr_r <= 0;
            out_valid  <= 0;
        end
        else if (reading) begin
            out_data  <= rb1_q_d;   // data from previous addr
            out_valid <= 1;

            if (out_addr_r == 8'd255) begin
                reading   <= 0;
                out_valid <= 0;
            end else begin
                out_addr_r <= out_addr_r + 1;
            end
        end else begin
            out_valid <= 0;
        end
    end
end

//assign rb1_raddr = reading ? out_addr_r : rb1_raddr_fsm;

always_comb begin
    if (reading)
        rb1_raddr_mux = out_addr_r;
    else
        rb1_raddr_mux = rb1_raddr_fsm;
end

endmodule

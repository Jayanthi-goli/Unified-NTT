/*
`timescale 1ns/1ps

module tb_unif_ntt_pipe;

  // -------------------------------------------------
  // Parameters
  // -------------------------------------------------
  localparam int N     = 256;
  localparam int Q     = 3329;
  localparam int INV_N = 3303;

  // -------------------------------------------------
  // Clock (100 MHz)
  // -------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk;

  // -------------------------------------------------
  // DUT signals
  // -------------------------------------------------
  logic rst_n;
  logic start;
  logic mode;                 // 0 = forward, 1 = inverse
  logic done;

  logic [15:0] host_in_data;
  logic        host_in_valid;

  logic [15:0] out_data;
  logic        out_valid;

  // -------------------------------------------------
  // DUT
  // -------------------------------------------------
  unif_ntt_top_pipe dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .mode(mode),
      .host_in_data(host_in_data),
      .host_in_valid(host_in_valid),
      .out_data(out_data),
      .out_valid(out_valid),
      .done(done)
  );

  // -------------------------------------------------
  // Test vectors
  // -------------------------------------------------
  logic [15:0] poly_in [0:N-1];
  logic [15:0] fwd_out [0:N-1];
  logic [15:0] inv_out [0:N-1];

  // -------------------------------------------------
  // Modular multiply
  // -------------------------------------------------
  function automatic [15:0] modmul(
      input [31:0] a,
      input [31:0] b
  );
      modmul = (a * b) % Q;
  endfunction

  // -------------------------------------------------
  // Feed polynomial (256 samples)
  // -------------------------------------------------
  task automatic feed_poly(input logic [15:0] vec [0:N-1]);
    integer i;
    begin
      host_in_valid = 0;
      @(posedge clk);

      for (i = 0; i < N; i++) begin
        @(posedge clk);
        host_in_data  <= vec[i];
        host_in_valid <= 1;
      end

      @(posedge clk);
      host_in_valid <= 0;
    end
  endtask

  // -------------------------------------------------
  // Capture exactly 256 outputs
  // -------------------------------------------------
  task automatic capture_outputs(output logic [15:0] vec [0:N-1]);
    integer k;
    begin
      k = 0;
      while (k < N) begin
        @(posedge clk);
        if (out_valid) begin
          vec[k] = out_data;
          k++;
        end
      end
    end
  endtask

  // -------------------------------------------------
  // Main test
  // -------------------------------------------------
  integer i;
  integer errors;

  initial begin
    // ---------------- Reset ----------------
    rst_n = 0;
    start = 0;
    mode  = 0;
    host_in_valid = 0;
    host_in_data  = 0;

    repeat (5) @(posedge clk);
    rst_n = 1;

    // ---------------- Input polynomial ----------------
    for (i = 0; i < N; i++)
      poly_in[i] = (i * 17 + 9) % Q;

    // =================================================
    // FORWARD NTT
    // =================================================
    $display("\n===== FORWARD NTT START =====");

    @(posedge clk);
    start <= 1;
    @(posedge clk);
    start <= 0;

    feed_poly(poly_in);
    wait (done);

    capture_outputs(fwd_out);
    $display("FORWARD NTT DONE");

    // =================================================
    // INVERSE NTT
    // =================================================
    $display("\n===== INVERSE NTT START =====");

    mode <= 1;

    @(posedge clk);
    start <= 1;
    @(posedge clk);
    start <= 0;

    feed_poly(fwd_out);
    wait (done);

    capture_outputs(inv_out);
    $display("INVERSE NTT DONE");

    // =================================================
    // SELF-CHECK (inverse scaling)
    // =================================================
    errors = 0;
    for (i = 0; i < N; i++) begin
      if (modmul(inv_out[i], INV_N) !== poly_in[i]) begin
        $display("ERROR @%0d : got %0d expected %0d",
                 i, modmul(inv_out[i], INV_N), poly_in[i]);
        errors++;
      end
    end

    if (errors == 0)
      $display("\n✅ NTT + INTT PASSED (256/256 correct)");
    else
      $display("\n❌ FAILED with %0d errors", errors);

    $finish;
  end

endmodule
////////////////////

`timescale 1ns/1ps

module tb_unif_ntt_pipe;

  // -------------------------------------------------
  // Parameters
  // -------------------------------------------------
  localparam int N     = 256;
  localparam int Q     = 3329;
  localparam int INV_N = 3303;

  // -------------------------------------------------
  // Clock (100 MHz)
  // -------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk;

  // -------------------------------------------------
  // DUT signals
  // -------------------------------------------------
  logic rst_n;
  logic start;
  logic mode;                 // 0 = forward, 1 = inverse
  logic done;

  logic [15:0] host_in_data;
  logic        host_in_valid;

  logic [15:0] out_data;
  logic        out_valid;

  // -------------------------------------------------
  // DUT
  // -------------------------------------------------
  unif_ntt_top_pipe dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .mode(mode),
      .host_in_data(host_in_data),
      .host_in_valid(host_in_valid),
      .out_data(out_data),
      .out_valid(out_valid),
      .done(done)
  );




  // -------------------------------------------------
  // Test vectors
  // -------------------------------------------------
  logic [15:0] poly_in [0:N-1];
  logic [15:0] fwd_out [0:N-1];
  logic [15:0] inv_out [0:N-1];

  // -------------------------------------------------
  // Modular multiply
  // -------------------------------------------------
  function automatic [15:0] modmul(
      input [31:0] a,
      input [31:0] b
  );
      modmul = (a * b) % Q;
  endfunction

  // -------------------------------------------------
  // Feed polynomial (256 samples) - SAFE
  // -------------------------------------------------
  task automatic feed_poly(input logic [15:0] vec [0:N-1]);
    integer i;
    begin
      host_in_valid <= 0;
      @(posedge clk);

      for (i = 0; i < N; i++) begin
        @(posedge clk);
        host_in_data  <= vec[i];
        host_in_valid <= 1;
      end

      @(posedge clk);
      host_in_valid <= 0;
    end
  endtask

  // -------------------------------------------------
  // Capture exactly 256 outputs - SAFE
  // -------------------------------------------------
  task automatic capture_outputs(output logic [15:0] vec [0:N-1]);
    integer k;
    begin
      k = 0;
      while (k < N) begin
        @(posedge clk);
        if (out_valid) begin
          vec[k] = out_data;
          k++;
        end
      end
    end
  endtask

  // -------------------------------------------------
  // MAIN TEST
  // -------------------------------------------------
  integer i;
  integer errors;

// -------------------------------------------------
// Bit-reversal for N = 256 (8 bits)
// -------------------------------------------------
function automatic [7:0] bitrev8(input [7:0] x);
    bitrev8 = {x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7]};
endfunction

  initial begin
    // ---------------- INIT ----------------
    rst_n = 0;
    start = 0;
    mode  = 0;
    host_in_valid = 0;
    host_in_data  = 0;

    repeat (10) @(posedge clk);
    rst_n = 1;

    // ---------------- Input polynomial ----------------
    for (i = 0; i < N; i++)
      poly_in[i] = (i * 17 + 9) % Q;

    // =================================================
    // FORWARD NTT
    // =================================================
    $display("\n===== FORWARD NTT START =====");

    feed_poly(poly_in);           // ✅ LOAD FIRST
    repeat (2) @(posedge clk);

    start <= 1;                   // ✅ THEN START
    @(posedge clk);
    start <= 0;

    wait (done);
    capture_outputs(fwd_out);

    $display("FORWARD NTT DONE");

    // =================================================
    // RESET BEFORE INVERSE (CRITICAL)
    // =================================================
    rst_n <= 0;
    repeat (10) @(posedge clk);
    rst_n <= 1;

    // =================================================
    // INVERSE NTT
    // =================================================
    $display("\n===== INVERSE NTT START =====");

    mode <= 1;

    feed_poly(fwd_out);           // ✅ LOAD FIRST
    repeat (2) @(posedge clk);

    start <= 1;
    @(posedge clk);
    start <= 0;

    wait (done);
    capture_outputs(inv_out);

    $display("INVERSE NTT DONE");

    // =================================================
  // =================================================
// SELF-CHECK (bit-reversal + inverse scaling)
// =================================================
errors = 0;
for (i = 0; i < N; i++) begin
    if (modmul(inv_out[bitrev8(i)], INV_N) !== poly_in[i]) begin
        $display("ERROR @%0d : got %0d expected %0d",
                 i,
                 modmul(inv_out[bitrev8(i)], INV_N),
                 poly_in[i]);
        errors++;
    end
end


if (errors == 0)
    $display("\n✅ NTT + INTT PASSED (256/256 correct)");
else
    $display("\n❌ FAILED with %0d errors", errors);


    $finish;
  end

endmodule
/////
///nainnnnn
`timescale 1ns/1ps
module tb_unif_ntt_pipe;

  // --------------------------------------------------
  // Parameters
  // --------------------------------------------------
  localparam int N     = 256;
  localparam int Q     = 3329;
  localparam int INV_N = 3303;

  // --------------------------------------------------
  // Clock
  // --------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk;

  // --------------------------------------------------
  // DUT signals
  // --------------------------------------------------
  logic rst_n, start, mode, done;
  logic [15:0] host_in_data;
  logic        host_in_valid;
  logic [15:0] out_data;
  logic        out_valid;

  // --------------------------------------------------
  // DUT
  // --------------------------------------------------
  unif_ntt_top_pipe dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .mode(mode),
      .host_in_data(host_in_data),
      .host_in_valid(host_in_valid),
      .out_data(out_data),
      .out_valid(out_valid),
      .done(done)
  );

  // --------------------------------------------------
  // Memories
  // --------------------------------------------------
  logic [15:0] poly_in [0:N-1];
  logic [15:0] fwd_out [0:N-1];
  logic [15:0] inv_out [0:N-1];

  // --------------------------------------------------
  // Functions
  // --------------------------------------------------
  function automatic [15:0] modmul(input [31:0] a, input [31:0] b);
    modmul = (a * b) % Q;
  endfunction

  function automatic [7:0] bitrev8(input [7:0] x);
    bitrev8 = {x[0],x[1],x[2],x[3],x[4],x[5],x[6],x[7]};
  endfunction

  // --------------------------------------------------
  // Task: feed polynomial (CLEAN timing)
  // --------------------------------------------------
  task automatic feed_poly(input logic [15:0] vec [0:N-1]);
    integer i;
    begin
      host_in_valid <= 0;
      host_in_data  <= 0;
      @(posedge clk);

      for (i = 0; i < N; i++) begin
        host_in_valid <= 1;
        host_in_data  <= vec[i];
        @(posedge clk);
      end

      host_in_valid <= 0;
      host_in_data  <= 0;
      @(posedge clk);
    end
  endtask

  // --------------------------------------------------
  // Task: capture outputs (NO double wait bug)
  // --------------------------------------------------
  task automatic capture_outputs(output logic [15:0] vec [0:N-1]);
    integer k;
    begin
      k = 0;

      // wait for FIRST valid
      wait (out_valid === 1'b1);

      while (k < N) begin
        @(posedge clk);
        if (out_valid) begin
          vec[k] = out_data;
          $display("CAPTURE[%0d] = %0d", k, out_data);
          k++;
        end
      end
    end
  endtask

  // --------------------------------------------------
  // Main test
  // --------------------------------------------------
  integer i, errors;

  initial begin
    // init
    rst_n = 0;
    start = 0;
    mode  = 0;
    host_in_valid = 0;
    host_in_data  = 0;

    repeat (10) @(posedge clk);
    rst_n = 1;

    // input polynomial
    for (i = 0; i < N; i++)
      poly_in[i] = (i*17 + 9) % Q;

    // clear arrays (important for waveform clarity)
    for (i = 0; i < N; i++) begin
      fwd_out[i] = 0;
      inv_out[i] = 0;
    end

    // ------------------------------------------------
    // FORWARD NTT
    // ------------------------------------------------
    $display("\n===== FORWARD NTT =====");
    feed_poly(poly_in);
    repeat (5) @(posedge clk);

    start <= 1;
    @(posedge clk);
    start <= 0;

    wait(done);
    capture_outputs(fwd_out);

    // ------------------------------------------------
    // INVERSE NTT
    // ------------------------------------------------
    $display("\n===== INVERSE NTT =====");
    mode <= 1;
    @(posedge clk);

    feed_poly(fwd_out);
    repeat (5) @(posedge clk);

    start <= 1;
    @(posedge clk);
    start <= 0;

    wait(done);
    capture_outputs(inv_out);

    // ------------------------------------------------
    // CHECK
    // ------------------------------------------------
    errors = 0;
    for (i = 0; i < N; i++) begin
      if (modmul(inv_out[bitrev8(i)], INV_N) !== poly_in[i]) begin
        $display("ERROR @%0d : got %0d expected %0d",
                 i,
                 modmul(inv_out[bitrev8(i)], INV_N),
                 poly_in[i]);
        errors++;
      end
    end

    if (errors == 0)
      $display("\n✅ PASS 256/256");
    else
      $display("\n❌ FAIL %0d", errors);

    $finish;
  end

endmodule

/////////
`timescale 1ns/1ps
module tb_unif_ntt_pipe;

  localparam int N = 256;
  localparam int Q = 3329;
  localparam int INV_N = 3303;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst_n, start, mode, done;
  logic [15:0] host_in_data;
  logic host_in_valid;
  logic [15:0] out_data;
  logic out_valid;
 int err = 0;
  unif_ntt_top_pipe dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .mode(mode),
    .host_in_data(host_in_data),
    .host_in_valid(host_in_valid),
    .out_data(out_data),
    .out_valid(out_valid),
    .done(done)
  );

  logic [15:0] poly [0:N-1];
  logic [15:0] fwd  [0:N-1];
  logic [15:0] inv  [0:N-1];

  function automatic [15:0] modmul(input [31:0] a, input [31:0] b);
    modmul = (a*b) % Q;
  endfunction

  // ---------------- FEED ----------------
  task feed(input logic [15:0] v[0:N-1]);
    host_in_valid <= 0;
    @(posedge clk);

    for (int i=0;i<N;i++) begin
      @(posedge clk);
      host_in_valid <= 1;
      host_in_data  <= v[i];
    end

    @(posedge clk);
    host_in_valid <= 0;
    host_in_data  <= '0;
  endtask

  // ---------------- CAPTURE ----------------
  task capture(output logic [15:0] v[0:N-1]);
    int k;
    k = 0;
    while (k < N) begin
      @(posedge clk);
      if (out_valid) begin
        v[k] = out_data;
        k++;
      end
    end
  endtask

  initial begin
    // RESET
    rst_n = 0; start = 0; mode = 0; host_in_valid = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;

    // INPUT
    for (int i=0;i<N;i++)
      poly[i] = (i*17+9)%Q;

    // ---------- FORWARD ----------
    feed(poly);
    repeat(5) @(posedge clk);   // 🔑 allow write settle

    start = 1;
    @(posedge clk);
    start = 0;

    wait(done);
    capture(fwd);

    // ---------- RESET ----------
    rst_n = 0;
    repeat(10) @(posedge clk);
    rst_n = 1;
    mode  = 1;

    // ---------- INVERSE ----------
    feed(fwd);
    repeat(5) @(posedge clk);   // 🔑 allow write settle

    start = 1;
    @(posedge clk);
    start = 0;

    wait(done);
    capture(inv);

    // ---------- CHECK ----------
   
    for (int i=0;i<N;i++)
      if (modmul(inv[i],INV_N) !== poly[i])
        err++;

    if (err == 0)
      $display("✅ PASS 256/256");
    else
      $display("❌ FAIL %0d", err);

    $finish;
  end
endmodule
*/
`timescale 1ns/1ps
module tb_unif_ntt_pipe;

  localparam int N = 256;
  localparam int Q = 3329;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst_n, start, mode, done;
  logic [15:0] host_in_data;
  logic host_in_valid;
  logic [15:0] out_data;
  logic out_valid;

  // DUT
  unif_ntt_top_pipe dut (
      .clk(clk),
      .rst_n(rst_n),
      .start(start),
      .mode(mode),
      .host_in_data(host_in_data),
      .host_in_valid(host_in_valid),
      .out_data(out_data),
      .out_valid(out_valid),
      .done(done)
  );

  logic [15:0] poly_in [0:N-1];
  logic [15:0] fwd_out [0:N-1];
  logic [15:0] inv_out [0:N-1];

  // ----------------------------------------------------------
  // Feed polynomial
  // ----------------------------------------------------------
  task automatic feed_poly(input logic [15:0] vec [0:N-1]);
    integer i;
    begin
      host_in_valid <= 0;
      host_in_data  <= '0;
      @(posedge clk);

      for (i = 0; i < N; i++) begin
        @(posedge clk);
        host_in_valid <= 1;
        host_in_data  <= vec[i];
      end

      @(posedge clk);
      host_in_valid <= 0;
      host_in_data  <= '0;
    end
  endtask

  // ----------------------------------------------------------
  // Capture outputs
  // ----------------------------------------------------------
  task automatic capture_outputs(output logic [15:0] vec [0:N-1]);
    integer k;
    begin
      k = 0;
      while (k < N) begin
        @(posedge clk);
        if (out_valid) begin
          vec[k] = out_data;
          k++;
        end
      end
    end
  endtask

  integer i;

  initial begin
    rst_n = 0; start = 0; mode = 0;
    host_in_valid = 0; host_in_data = 0;

    repeat (10) @(posedge clk);
    rst_n = 1;

    // Create input polynomial
    for (i = 0; i < N; i++)
      poly_in[i] = (i*17 + 9) % Q;

    // ----------------------------------------------------------
    // PRINT INPUT
    // ----------------------------------------------------------
    $display("\n========== INPUT POLY ==========");
    for (i = 0; i < 16; i++)
      $display("poly_in[%0d] = %0d", i, poly_in[i]);

    // ----------------------------------------------------------
    // FORWARD NTT
    // ----------------------------------------------------------
    feed_poly(poly_in);
    repeat (5) @(posedge clk);

    start <= 1;
    @(posedge clk);
    start <= 0;

    wait(done);
    capture_outputs(fwd_out);

    $display("\n========== FORWARD OUTPUT ==========");
    for (i = 0; i < 16; i++)
      $display("fwd_out[%0d] = %0d", i, fwd_out[i]);

    // ----------------------------------------------------------
    // RESET
    // ----------------------------------------------------------
    rst_n <= 0;
    repeat (10) @(posedge clk);
    rst_n <= 1;

    // ----------------------------------------------------------
    // INVERSE NTT
    // ----------------------------------------------------------
    mode <= 1;
    feed_poly(fwd_out);
    repeat (5) @(posedge clk);

    start <= 1;
    @(posedge clk);
    start <= 0;

    wait(done);
    capture_outputs(inv_out);

    $display("\n========== INVERSE OUTPUT ==========");
    for (i = 0; i < 16; i++)
      $display("inv_out[%0d] = %0d", i, inv_out[i]);

    $display("\nSimulation Finished.");
    $finish;
  end

endmodule

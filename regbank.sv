/*`timescale 1ns/1ps
module regbank #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 128
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     wen,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [WIDTH-1:0]         wdata,

    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0]         rdata
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // WRITE
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++)
                mem[i] <= '0;
        end else if (wen) begin
            mem[waddr] <= wdata;
        end
    end

    // SYNCHRONOUS READ
    always_ff @(posedge clk) begin
        rdata <= mem[raddr];
    end

endmodule

////
*/
module regbank #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 256
)(
    input  logic clk,
    input  logic wen,
    input  logic rst_n,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [WIDTH-1:0] wdata,
    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0] rdata
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // synchronous write (ONLY ONE)
  integer i;

always_ff @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] <= 0;
    end
    else if (wen) begin
        mem[waddr] <= wdata;
        $display("WRITE: addr=%0d data=%0d time=%0t",
                 waddr, wdata, $time);
    end
end

    // asynchronous read (correct for your FSM)
    assign rdata = mem[raddr];

endmodule


/*
module regbank #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 128
)(
    input  logic clk,
    input  logic wen,
    input  logic [$clog2(DEPTH)-1:0] waddr,
    input  logic [WIDTH-1:0] wdata,
    input  logic [$clog2(DEPTH)-1:0] raddr,
    output logic [WIDTH-1:0] rdata
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wen)
            mem[waddr] <= wdata;
        rdata <= mem[raddr];   // synchronous read → BRAM OK
    end

endmodule
*/
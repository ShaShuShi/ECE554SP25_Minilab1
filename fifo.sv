module FIFO
#(
  parameter DEPTH = 8,
  parameter DATA_WIDTH = 8
)
(
  input clk,
  input rst_n,
  input rden,
  input wren,
  input [DATA_WIDTH-1:0] i_data,
  output reg [DATA_WIDTH-1:0] o_data,
  output full,
  output empty
);

  // Internal memory array for the FIFO
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  // Pointers for write and read operations
  reg [$clog2(DEPTH)-1:0] wr_ptr = 0;
  reg [$clog2(DEPTH)-1:0] rd_ptr = 0;

  reg [15:0] wr = 0;
  reg [15:0] rd = 0;

  // Full and empty status signals
  reg full_flag = 0;
  reg empty_flag = 1;

  // Assign status outputs
  assign full = full_flag;
  assign empty = empty_flag;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset logic
      wr_ptr <= 0;
      rd_ptr <= 0;
      full_flag <= 0;
      empty_flag <= 1;
      wr <= 0;
      rd <= 0;
    end else begin
      // Write operation
      if (wren && !full_flag) begin
        mem[wr_ptr] <= i_data;
        wr_ptr <= (wr_ptr + 1) % DEPTH;
	wr <= wr + 1;
        empty_flag <= 0;
        if (wr == rd + DEPTH - 1) begin
          full_flag <= 1;
        end
      end

      // Read operation
      if (rden && !empty_flag) begin
        o_data <= mem[rd_ptr];
        rd_ptr <= (rd_ptr + 1) % DEPTH;
	rd <= rd + 1;
        full_flag <= 0;
        if (rd == wr - 1) begin
          empty_flag <= 1;
        end
      end
    end
  end

endmodule



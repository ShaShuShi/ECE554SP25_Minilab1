`timescale 1 ps / 1 ps

module MVM_tb;
  // Parameters (for reference)
  parameter DATA_WIDTH = 8;
  parameter NUM_MAC    = 8;              // Number of MAC units (and FIFOs)
  parameter DEPTH      = 8;              // Number of memory rows to process
  parameter ACC_WIDTH  = DATA_WIDTH * 3; // MAC accumulator width (24 bits)

  // Clock and control signals
  reg         clk;
  reg  [3:0]  KEY;
  reg  [9:0]  SW;

  // HEX display outputs from the top-level design
  wire [6:0]  HEX0;
  wire [6:0]  HEX1;
  wire [6:0]  HEX2;
  wire [6:0]  HEX3;
  wire [6:0]  HEX4;
  wire [6:0]  HEX5;

  // Instantiate the top-level design (Minilab1)
  Minilab1 IMinilab (
    .CLOCK_50(clk),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5),
    .KEY(KEY),
    .SW(SW)
  );

  // Clock generation: 10 ps period (adjust as needed)
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  initial begin
    // Initialize signals
    KEY = 4'b0000;   // Hold reset active (KEY[0] is active-low reset)
    SW  = 10'b0;     // No MAC selected initially

    // Hold reset for a few clock cycles, then release it.
    #20;
    KEY = 4'b0001;   // Release reset (rst_n becomes 1 in Minilab1)

    // Allow time for the design to initialize and fill FIFOs.
    #100;
    
    // Wait enough time for the operation to complete.
    #2500;
    
    // Now drive SW to select different MAC outputs.
    // In this example, we use SW[7:0] as a one-hot selector.
    // Only one switch is asserted at a time.
    SW = 10'b0000000000;
    #50; 
    SW[0] = 1;  // Select MAC0
    #50;
    SW[0] = 0; 
    #20; 
    SW[1] = 1;  // Select MAC1
    #50;
    SW[1] = 0; 
    #20; 
    SW[2] = 1;  // Select MAC2
    #50;
    SW[2] = 0; 
    #20; 
    SW[3] = 1;  // Select MAC3
    #50;
    SW[3] = 0; 
    #20; 
    SW[4] = 1;  // Select MAC4
    #50;
    SW[4] = 0; 
    #20; 
    SW[5] = 1;  // Select MAC5
    #50;
    SW[5] = 0; 
    #20; 
    SW[6] = 1;  // Select MAC6
    #50;
    SW[6] = 0; 
    #20; 
    SW[7] = 1;  // Select MAC7
    #50;
    SW[7] = 0;
    #50;
    
    $finish;
  end

endmodule


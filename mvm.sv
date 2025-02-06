module MVM #(
  parameter DATA_WIDTH = 8,
  parameter NUM_MAC    = 8,  // Number of MAC units (also number of A FIFO rows)
  parameter DEPTH      = 8   // Memory row depth per FIFO
)(
  input  logic         clk,
  input  logic         rst_n,
  input  logic         Clr,
  // Final results from each MAC as a single flattened bus
  output logic [(NUM_MAC*DATA_WIDTH*3)-1:0] result
);

  // Internal storage for final results (2D array style)
  logic [DATA_WIDTH*3-1:0] result_ff [NUM_MAC-1:0];

  //=====================================================================
  // ROM (mem_wrapper) Interface
  //=====================================================================
  reg  [31:0] address_index;  // Each address yields one 64-bit word
  reg         read_mem;
  wire        mem_valid;
  wire        mem_wait_request;
  wire [63:0] read_data_mem;
  
  mem_wrapper mem_inst (
    .clk           (clk),
    .reset_n       (rst_n),
    .address       (address_index[3:0]),
    .read          (read_mem),
    .readdata      (read_data_mem),
    .readdatavalid (mem_valid),
    .waitrequest   (mem_wait_request)
  );

  //=====================================================================
  // FIFOs for Matrix A Data (unchanged except indexing later)
  //=====================================================================
  logic [DATA_WIDTH-1:0] fifoA_data_in [NUM_MAC-1:0];
  logic                  fifoA_wren    [NUM_MAC-1:0];
  logic                  fifoA_rden    [NUM_MAC-1:0];
  logic [DATA_WIDTH-1:0] fifoA_out     [NUM_MAC-1:0];
  wire                   fifoA_full    [NUM_MAC-1:0];
  wire                   fifoA_empty   [NUM_MAC-1:0];
  
  genvar i;
  generate
    for(i = 0; i < NUM_MAC; i = i + 1) begin : A_FIFOs
      FIFO #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
      ) fifo_inst (
        .clk    (clk),
        .rst_n  (rst_n),
        .rden   (fifoA_rden[i]),
        .wren   (fifoA_wren[i]),
        .i_data (fifoA_data_in[i]),
        .o_data (fifoA_out[i]),
        .full   (fifoA_full[i]),
        .empty  (fifoA_empty[i])
      );
    end
  endgenerate
  
  //=====================================================================
  // FIFO for Vector B Data (B now comes from memory)
  //=====================================================================
  logic [DATA_WIDTH-1:0] fifoB_data_in;
  logic                  fifoB_wren;
  logic                  fifoB_rden;
  wire [DATA_WIDTH-1:0]  fifoB_out;
  wire                   fifoB_full;
  wire                   fifoB_empty;
  
  FIFO #(
    .DEPTH(DEPTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) fifoB (
    .clk   (clk),
    .rst_n (rst_n),
    .rden  (fifoB_rden),
    .wren  (fifoB_wren),
    .i_data(fifoB_data_in),
    .o_data(fifoB_out),
    .full  (fifoB_full),
    .empty (fifoB_empty)
  );
  
  // A counter to step through the 8 bytes of the current row.
  reg [2:0] byte_counter;  // Counts from 0 to 7
  
  //=====================================================================
  // Main State Machine: INIT --> FILL --> EXEC --> DONE
  //=====================================================================
  typedef enum logic [1:0] {INIT, FILL, EXEC, DONE} state_t;
  state_t state, next_state;
  
  // Global enable (asserted when FIFOs are loaded)
  reg global_en;
  reg shift_start;
  logic disable_read;
  
  //=====================================================================
  // Pipelined Enable and B Propagation 
  //=====================================================================
  logic en_pipeline [NUM_MAC-1:0];
  logic [3:0] add_count [NUM_MAC - 1:0];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      en_pipeline[0] <= 0;
      for (int m = 1; m < NUM_MAC; m = m + 1) begin
        en_pipeline[m-1] <= 0;
        add_count[m-1]  <= 4'b0000;
      end
    end else if (state == EXEC) begin
      if(add_count[0] < 4'b1000) begin
        en_pipeline[0] <= global_en;
      end
      for (int m = 1; m < NUM_MAC; m = m + 1) begin
        en_pipeline[m] <= en_pipeline[m-1];
        if(en_pipeline[m-1]) begin
          add_count[m-1] <= add_count[m-1] + 1'b1;
          if(add_count[m-1] > 3'b111) begin
            en_pipeline[m-1] <= 0;
          end
        end
      end
    end else begin
      for (int m = 0; m < NUM_MAC; m = m + 1)
        en_pipeline[m] <= 0;
    end
  end
  
  // The b_pipeline now gets its input from the B FIFO (loaded from memory row 0).
  logic [DATA_WIDTH-1:0] b_pipeline [NUM_MAC-1:0];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_pipeline[0] <= 0;
      for (int m = 1; m < NUM_MAC; m = m + 1)
        b_pipeline[m] <= 0;
    end else if (state == EXEC) begin
      b_pipeline[0] <= fifoB_out;
      for (int m = 1; m < NUM_MAC; m = m + 1)
        b_pipeline[m] <= b_pipeline[m-1];
    end else begin
      for (int m = 0; m < NUM_MAC; m = m + 1)
        b_pipeline[m] <= 0;
    end
  end
  
  //-------------------------------------------------------------------------
  // FILL State: Buffering and Shifting out Bytes into FIFOs
  //-------------------------------------------------------------------------
  // In this state, the memory words are captured into a double buffer.
  // The bytes of the current row are shifted out to either the B FIFO
  // (for address_index==0) or the A FIFOs (for address_index 1..NUM_MAC).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= INIT;
      address_index <= 0;
      byte_counter  <= 0;
      global_en     <= 0;
      // Initialize FIFO enables
      for (int j = 0; j < NUM_MAC; j = j + 1) begin
        fifoA_wren[j] <= 0;
        fifoA_rden[j] <= 0;
      end
      fifoB_wren <= 0;
      fifoB_rden <= 0;
    end else begin
      state <= next_state;
      case (state)
        //---------------------------------------------------------------------
        // INIT: Begin memory read.
        //---------------------------------------------------------------------
        INIT: begin
          read_mem <= 1;
          disable_read <= 0;
        end

        //---------------------------------------------------------------------
        // FILL: Load FIFOs from Memory via Buffered Rows.
        //---------------------------------------------------------------------
        FILL: begin
          if (~disable_read) begin
            read_mem <= 0;
            disable_read <= 1;
          end
          if (mem_valid & ~mem_wait_request) begin
            shift_start <= 1;
            read_mem <= 0;
          end
          if (shift_start) begin
            if (address_index == 0 & ~fifoB_full) begin
              fifoB_data_in <= read_data_mem[byte_counter*8 +: 8];
              fifoB_wren    <= 1;
              read_mem      <= 0;
            end else begin
              // For addresses 1 to NUM_MAC, load A FIFOs.
              // The index for the A FIFOs is (address_index - 1).
              fifoB_wren    <= 0;
              fifoA_data_in[address_index-1] <= read_data_mem[byte_counter*8 +: 8];
              fifoA_wren[address_index-1]    <= 1;
              read_mem      <= 0;
            end
            // Advance byte counter.
            if (byte_counter == 7) begin
              byte_counter  <= 0;
              address_index <= address_index + 1;
              read_mem      <= 1;
              shift_start   <= 0;
            end else begin
              byte_counter <= byte_counter + 1;
              read_mem     <= 0;
            end
            if (address_index == 0) begin
              fifoB_wren <= 1;
            end
          end else if (byte_counter != 7) begin
            read_mem <= 0;
          end

          // Disable reading from the B FIFO during FILL.
          fifoB_rden <= 0;
        end

        //---------------------------------------------------------------------
        // EXEC: FIFOs are loaded. Stop memory reads and enable FIFO reads.
        //---------------------------------------------------------------------
        EXEC: begin
          // Initialize FIFO enables
          for (int j = 0; j < NUM_MAC; j = j + 1) begin
            fifoA_wren[j] <= 0;
          end
          fifoB_wren <= 0;

          // Stop further memory reads.
          global_en <= 1;
          read_mem  <= 0;
          // Read FIFO A with the same relative delay as the B pipeline:
          // FIFO 0 gets the ?immediate? data, and FIFO k (for k>=1)
          // is read one cycle later.
          fifoA_rden[0] <= global_en;
          for (int k = 1; k < NUM_MAC; k = k + 1) begin
            fifoA_rden[k] <= en_pipeline[k-1];
          end
          // Enable reading from the B FIFO.
          fifoB_rden <= 1;
        end

        //---------------------------------------------------------------------
        // DONE: Processing complete. Stop FIFO reads.
        //---------------------------------------------------------------------
        DONE: begin
          global_en <= 0;
          for (int k = 0; k < NUM_MAC; k = k + 1)
            fifoA_rden[k] <= 0;
          fifoB_rden <= 0;
        end

        default: begin
          global_en <= 0;
        end
      endcase
    end
  end
  
  //=====================================================================
  // Next-State Logic
  //=====================================================================
  always_comb begin
    next_state = state;
    case (state)
      INIT: begin
        if (read_mem)
          next_state = FILL;
      end
      FILL: begin
        // We have loaded one row for B (address_index==0) plus NUM_MAC rows for A.
        if (&{fifoA_full[0], fifoA_full[1], fifoA_full[2], fifoA_full[3],
              fifoA_full[4], fifoA_full[5], fifoA_full[6], fifoA_full[7]})
          next_state = EXEC;
        else
          next_state = FILL;
      end
      EXEC: begin
        // When all A FIFOs become empty, processing is complete.
        if (&{fifoA_empty[0], fifoA_empty[1], fifoA_empty[2], fifoA_empty[3],
              fifoA_empty[4], fifoA_empty[5], fifoA_empty[6], fifoA_empty[7]})
          next_state = DONE;
        else
          next_state = EXEC;
      end
      DONE: begin
        next_state = DONE;
      end
      default: next_state = FILL;
    endcase
  end
  
  //=====================================================================
  // MAC Array Instantiation 
  //=====================================================================
  logic [DATA_WIDTH*3-1:0] mac_out [NUM_MAC-1:0];
  
  genvar j;
  generate
    for (j = 0; j < NUM_MAC; j = j + 1) begin : MAC_ARRAY
      MAC #(
        .DATA_WIDTH(DATA_WIDTH)
      ) mac_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .En    (en_pipeline[j]),
        .Clr   (Clr),
        .Ain   (fifoA_out[j]),
        .Bin   (b_pipeline[j]),
        .Cout  (mac_out[j])
      );
    end
  endgenerate
  
  //=====================================================================
  // Capture/Output Final Results
  //=====================================================================
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int k = 0; k < NUM_MAC; k = k + 1)
        result_ff[k] <= '0;
    end else if (state == DONE) begin
      for (int k = 0; k < NUM_MAC; k = k + 1)
        result_ff[k] <= mac_out[k];
    end
  end

  // Flatten the 2D result_ff array into the 1D output "result".
  // Each MAC result occupies DATA_WIDTH*3 bits in the output.
  always_comb begin
    for (int k = 0; k < NUM_MAC; k = k + 1) begin
      result[k*DATA_WIDTH*3 +: DATA_WIDTH*3] = result_ff[k];
    end
  end

endmodule


// ***************************************************************************
//
//        UCLA CDSC Microbenchmark AFU
//
// Engineer:            Peng Wei
// Create Date:         Oct 13, 2015
// Module Name:         micro_bench
// Description:         top level wrapper for Microbenchmark AFU
// ***************************************************************************
//
// CSR Address Map -- Change v1.1
//------------------------------------------------------------------------------------------
//      Address[15:0] Attribute         Name                    Comments
//     'h1A00          WO                CSR_AFU_DSM_BASEL       Lower 32-bits of AFU DSM base address. The lower 6-bbits are 4x00 since the address is cache aligned.
//     'h1A04          WO                CSR_AFU_DSM_BASEH       Upper 32-bits of AFU DSM base address.
//     'h1A20:         WO                CSR_SRC_ADDR            Start physical address for source buffer. All read requests are targetted to this region.
//     'h1A24:         WO                CSR_DST_ADDR            Start physical address for destination buffer. All write requests are targetted to this region.
//     'h1A2c:         WO                CSR_CTL                 Controls test flow, start, stop, force completion
//     'h1A30:         WO                CSR_DATA_SIZE           Input/Output data size
//     'h1A34:         WO                CSR_LOOP_NUM            Loop number
//     
//
// DSM Offeset Map -- Change v1.1
//------------------------------------------------------------------------------------------
//      Byte Offset   Attribute         Name                  Comments
//      0x00          RO                DSM_AFU_ID            non-zero value to uniquely identify the AFU
//      0x40          RO                DSM_STATUS            test status and error register
//
//
// 1 Cacheline = 64B i.e 2^6 Bytes
// Let 2^N be the number of cachelines in the source & destination buffers. Then select CSR_SRC_ADDR & CSR_DEST_ADDR to be 2^(N+6) aligned.
//
// CSR_SRC_ADDR:
// [31:0]   WO   2^(N+6)B aligned address points to the start of read buffer
//
// CSR_DST_ADDR:
// [31:0]   WO   2^(N+6)B aligned address points to the start of write buffer
//
// CSR_CTL:
// [31:3]   WO    Rsvd
// [2]      WO    Force test completion. Writes test completion flag and other performance counters to csr_stat. It appears to be like a normal test completion.
// [1]      WO    Starts test execution.
// [0]      WO    Active low test Reset. All configuration parameters change to reset defaults.
//
// CSR_CFG:
// [29]     WO    cr_interrupt_testmode - used to test interrupt. Generates an interrupt at end of each test.
// [28]     WO    cr_interrupt_on_error - send an interrupt when error detected
// [27:20]  WO    cr_test_cfg  -may be used to configure the behavior of each test mode
// [10:9]   WO    cr_rdsel     -configure read request type. 0- RdLine_S, 1- RdLine_I, 2- RdLine_O, 3- Mixed mode
// [8]      WO    cr_delay_en  -enable random delay insertion between requests
// [4:2]    WO    cr_mode      -configures test mode
// [1]      WO    cr_cont      - 1- test rollsover to start address after it reaches the CSR_NUM_LINES count. Such a test terminates only on an error.
//                               0- test terminates, updated the status csr when CSR_NUM_LINES count is reached.
// [0]      WO    cr_wrthru_en -switch between write back to write through request type. 0- Wr Back, 1- WrThru
//
// DSM_STATUS:
// [511:256] RO  Error dump from Test Mode
// [255:224] RO  end overhead
// [223:192] RO  start overhead
// [191:160] RO  Number of writes
// [159:128] RO  Number of reads
// [127:64]  RO  Number of clocks
// [63:32]   RO  test error register
// [31:0]    RO  test completion flag
//
// DSM_AFU_ID:
// [512:144] RO   Zeros
// [143:128] RO   Version
// [127:0]   RO   AFU ID 

module micro_bench #(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, DATA_WIDTH =512)
(
    // ---------------------------global signals-------------------------------------------------
    clk,                              //              in    std_logic;  -- Core clock
    reset_n,                          //              in    std_logic;  -- Use SPARINGLY only for control
    // ---------------------------IF signals between SPL and FPL  --------------------------------
    rb2cf_C0RxHdr,                    // [RXHDR_WIDTH-1:0]   cci_intf:           Rx header to SPL channel 0
    rb2cf_C0RxData,                   // [DATA_WIDTH -1:0]   cci_intf:           Rx data response to SPL | no back pressure
    rb2cf_C0RxWrValid,                //                     cci_intf:           Rx write response enable
    rb2cf_C0RxRdValid,                //                     cci_intf:           Rx read response enable
    rb2cf_C0RxCfgValid,               //                     cci_intf:           Rx config response enable
    rb2cf_C0RxUMsgValid,              //                     cci_intf:           Rx UMsg valid
    rb2cf_C0RxIntrValid,                //                     cci_intf:           Rx interrupt valid
    rb2cf_C1RxHdr,                    // [RXHDR_WIDTH-1:0]   cci_intf:           Rx header to SPL channel 1
    rb2cf_C1RxWrValid,                //                     cci_intf:           Rx write response valid
    rb2cf_C1RxIntrValid,                //                     cci_intf:           Rx interrupt valid

    cf2ci_C0TxHdr,                    // [TXHDR_WIDTH-1:0]   cci_intf:           Tx Header from SPL channel 0
    cf2ci_C0TxRdValid,                //                     cci_intf:           Tx read request enable
    cf2ci_C1TxHdr,                    //                     cci_intf:           Tx Header from SPL channel 1
    cf2ci_C1TxData,                   //                     cci_intf:           Tx data from SPL
    cf2ci_C1TxWrValid,                //                     cci_intf:           Tx write request enable
    cf2ci_C1TxIntrValid,              //                     cci_intf:           Tx interrupt valid
    ci2cf_C0TxAlmFull,                //                     cci_intf:           Tx memory channel 0 almost full
    ci2cf_C1TxAlmFull,                //                     cci_intf:           TX memory channel 1 almost full

    ci2cf_InitDn                      // Link initialization is complete
);

    input                        clk;                  //              in    std_logic;  -- Core clock
    input                        reset_n;              //              in    std_logic;  -- Use SPARINGLY only for control

    input [RXHDR_WIDTH-1:0]      rb2cf_C0RxHdr;        // [RXHDR_WIDTH-1:0]cci_intf:           Rx header to SPL channel 0
    input [DATA_WIDTH -1:0]      rb2cf_C0RxData;       // [DATA_WIDTH -1:0]cci_intf:           data response to SPL | no back pressure
    input                        rb2cf_C0RxWrValid;    //                  cci_intf:           write response enable
    input                        rb2cf_C0RxRdValid;    //                  cci_intf:           read response enable
    input                        rb2cf_C0RxCfgValid;   //                  cci_intf:           config response enable
    input                        rb2cf_C0RxUMsgValid;  //                  cci_intf:           Rx UMsg valid
    input                        rb2cf_C0RxIntrValid;    //                  cci_intf:           interrupt response enable
    input [RXHDR_WIDTH-1:0]      rb2cf_C1RxHdr;        // [RXHDR_WIDTH-1:0]cci_intf:           Rx header to SPL channel 1
    input                        rb2cf_C1RxWrValid;    //                  cci_intf:           write response valid
    input                        rb2cf_C1RxIntrValid;    //                  cci_intf:           interrupt response valid

    output [TXHDR_WIDTH-1:0]     cf2ci_C0TxHdr;        // [TXHDR_WIDTH-1:0]cci_intf:           Tx Header from SPL channel 0
    output                       cf2ci_C0TxRdValid;    //                  cci_intf:           Tx read request enable
    output [TXHDR_WIDTH-1:0]     cf2ci_C1TxHdr;        //                  cci_intf:           Tx Header from SPL channel 1
    output [DATA_WIDTH -1:0]     cf2ci_C1TxData;       //                  cci_intf:           Tx data from SPL
    output                       cf2ci_C1TxWrValid;    //                  cci_intf:           Tx write request enable
    output                       cf2ci_C1TxIntrValid;  //                  cci_intf:           Tx interrupt valid
    input                        ci2cf_C0TxAlmFull;    //                  cci_intf:           Tx memory channel 0 almost full
    input                        ci2cf_C1TxAlmFull;    //                  cci_intf:           TX memory channel 1 almost full

    input                        ci2cf_InitDn;         //                  cci_intf:           Link initialization is complete

    assign cf2ci_C1TxIntrValid = 'b0;

    //----------------------------------------------------------------------------------------------------------------------
    // Microbenchmark AFU ID
    // It is important to keep the least significant 4 bits NON-ZERO to be compliant with CCIDemo.cpp
    //
    localparam       MICRO_BENCH         = 128'h2015_1013_900d_beef_a000_b000_c000_d000;
    localparam       VERSION             = 16'h0001;
    
    //---------------------------------------------------------
    // CCI-S Request Encodings  ***** DO NOT MODIFY ******
    //---------------------------------------------------------
    localparam       WrThru              = 4'h1;
    localparam       WrLine              = 4'h2;
    localparam       RdLine              = 4'h4;
    localparam       WrFence             = 4'h5;
    
    //--------------------------------------------------------
    // CCI-S Response Encodings  ***** DO NOT MODIFY ******
    //--------------------------------------------------------
    localparam      RSP_CSR              = 4'h0;
    localparam      RSP_WRITE            = 4'h1;
    localparam      RSP_READ             = 4'h4;
    
    //---------------------------------------------------------
    // Default Values ****** May be MODIFIED ******* 
    //---------------------------------------------------------
    localparam      DEF_SRC_ADDR         = 32'h0400_0000;           // Read data starting from here. Cache aligned Address
    localparam      DEF_DST_ADDR         = 32'h0800_0000;           // Copy data to here. Cache aligned Address

    localparam      DEF_DSM_BASE         = 32'h04ff_ffff;           // default status address
    
    //---------------------------------------------------------
    // CSR Address Map ***** DO NOT MODIFY *****
    //---------------------------------------------------------
    localparam      CSR_AFU_DSM_BASEL    = 16'h1a00;                 // WO - Lower 32-bits of AFU DSM base address. The lower 6-bbits are 4x00 since the address is cache aligned.
    localparam      CSR_AFU_DSM_BASEH    = 16'h1a04;                 // WO - Upper 32-bits of AFU DSM base address.
    localparam      CSR_SRC_ADDR         = 16'h1a20;                 // WO   Reads are targetted to this region 
    localparam      CSR_DST_ADDR         = 16'h1a24;                 // WO   Writes are targetted to this region
    localparam      CSR_CTL              = 16'h1a2c;                 // WO   Control CSR to start n stop the test
    localparam      CSR_DATA_SIZE        = 16'h1a30;                 // WO   Input/Output data size
    localparam      CSR_LOOP_NUM         = 16'h1a34;                 // WO   Loop number
    
    //----------------------------------------------------------------------------------
    // Device Status Memory (DSM) Address Map ***** DO NOT MODIFY *****
    // Physical address = value at CSR_AFU_DSM_BASE + Byte offset
    //----------------------------------------------------------------------------------
    //                                     Byte Offset                 Attribute    Width   Comments
    localparam      DSM_AFU_ID           = 32'h0;                   // RO           32b     non-zero value to uniquely identify the AFU
    localparam      DSM_STATUS           = 32'h40;                  // RO           512b    test status and error info
    
    //----------------------------------------------------------------------------------------------------------------------
    
    reg     [DATA_WIDTH-1:0]        cf2ci_C1TxData;
    reg     [TXHDR_WIDTH-1:0]       cf2ci_C1TxHdr;
    reg                             cf2ci_C1TxWrValid;
    reg     [TXHDR_WIDTH-1:0]       cf2ci_C0TxHdr;
    reg                             cf2ci_C0TxRdValid;
    
    reg                             dsm_base_valid;
    reg                             dsm_base_valid_q;
    reg                             afuid_updtd;
    reg                             task_completed;
    reg                             task_completed_d;
    
    reg     [63:0]                  cr_dsm_base;            // a00h, a04h - DSM base address
    reg     [31:0]                  cr_src_address;         // a20h - source buffer address
    reg     [31:0]                  cr_dst_address;         // a24h - destn buffer address
    reg     [31:0]                  cr_ctl  = 0;            // a2ch - control register to start and stop the test
    reg     [31:0]                  cr_data_size;           // a30h - input/output data size (unit: byte)
    reg     [31:0]                  cr_loop_num;            // a34h - specify how many times the kernel needs to be repeated
    wire                            test_go = cr_ctl[1];    // When 0, it allows reconfiguration of test parameters.

    //CCI Read Address Offset
    reg     [31:0]                  RdAddrOffset;
    //CCI Read ID
    reg     [13:0]                  RdReqId;
    //CCI Read Type
    wire    [3:0]                   rdreq_type = RdLine;
    //CCI Read Date
    reg     [DATA_WIDTH-1:0]        RdData;

    //CCI Write Address Offset
    reg     [31:0]                  WrAddrOffset;
    //CCI Write ID
    reg     [13:0]                  WrReqId;
    //CCI Write Type
    wire    [3:0]                   wrreq_type = WrLine;
    //CCI Write Date
    reg     [DATA_WIDTH-1:0]        WrData;

    wire    [31:0]                  ds_afuid_address = dsm_offset2addr(DSM_AFU_ID,cr_dsm_base);     // 0h - afu id is written to this address
    wire    [31:0]                  ds_stat_address = dsm_offset2addr(DSM_STATUS,cr_dsm_base);      // 40h - test status is written to this address
    wire                            re2xy_go = test_go & afuid_updtd & ci2cf_InitDn;                // After initializing DSM, we can do actual tasks on AFU
    reg                             WrHdr_valid;                                                    // 1: Valid Write Request
    reg                             RdHdr_valid;                                                    // 1: Valid Read Request

    //-------------------------
    //CSR Register Handling
    //-------------------------
    always @(posedge clk)                                              
    begin                                                                   
        if(!reset_n)
        begin
            cr_dsm_base     <= DEF_DSM_BASE;
            cr_src_address  <= DEF_SRC_ADDR;
            cr_dst_address  <= DEF_DST_ADDR;
            cr_ctl          <= 'b0;
            cr_data_size    <= 'h4000;
            cr_loop_num     <= 'b1;
            dsm_base_valid  <= 'b0;
        end
        else
        begin  
            //control register can be written anytime after resetting
            if(rb2cf_C0RxCfgValid)
                case({rb2cf_C0RxHdr[13:0],2'b00})         /* synthesis parallel_case */
                    CSR_CTL          :   cr_ctl             <= rb2cf_C0RxData[31:0];
                endcase
            if(~test_go) // Configuration Mode, following CSRs can only be updated in this mode
            begin
                if(rb2cf_C0RxCfgValid)
                case({rb2cf_C0RxHdr[13:0],2'b00})         /* synthesis parallel_case */
                    CSR_SRC_ADDR:        cr_src_address     <= rb2cf_C0RxData[31:0];
                    CSR_DST_ADDR:        cr_dst_address     <= rb2cf_C0RxData[31:0];
                    CSR_AFU_DSM_BASEH:   cr_dsm_base[63:32] <= rb2cf_C0RxData[31:0];
                    CSR_AFU_DSM_BASEL:begin
                                         cr_dsm_base[31:0]  <= rb2cf_C0RxData[31:0];
                                         dsm_base_valid     <= 'b1;
                                      end
                    CSR_DATA_SIZE:       cr_data_size       <= rb2cf_C0RxData[31:0];
                    CSR_LOOP_NUM:        cr_loop_num        <= rb2cf_C0RxData[31:0];
                endcase
            end
        end
    end

    //-------------------------
    // Data Processing
    //-------------------------

    reg [31:0] cache_line_counter; // increment rate = 'd64
    reg [31:0] cache_line_counter_d;
    reg [31:0] integer_counter;
    reg [31:0] integer_counter_d;
    reg [DATA_WIDTH-1:0] final_result;
    reg [DATA_WIDTH-1:0] final_result_d;
    reg [2:0]  cur_state;
    reg [2:0]  next_state;

    localparam RESET = 'd0;
    localparam IDLE  = 'd1;
    localparam WAIT  = 'd2;
    localparam CALC  = 'd3;
    localparam WRITE = 'd4;
    localparam DONE  = 'd5;

    // Sequential Logic
    always @ (posedge clk) 
    begin
        if (!reset_n)
        begin
            cache_line_counter <= 'b0;
            integer_counter    <= 'b0;
            final_result       <= {(DATA_WIDTH/32){32'h900dbeef}};
            cur_state          <= RESET;
        end
        else
        begin
            cache_line_counter <= cache_line_counter_d;
            integer_counter    <= integer_counter_d;
            final_result       <= final_result_d;
            cur_state          <= next_state;
        end
    end

    // Combinatorial Logic
    always @ (*)
    begin
        next_state           = cur_state;
        case(cur_state)                             /* synthesis parallel_case */
            RESET:   
            begin
              if(re2xy_go) // ready to go
                next_state = IDLE; 
            end
            IDLE:
            begin
              if(!ci2cf_C0TxAlmFull) // read request sent
                next_state = WAIT;
            end
            WAIT:
            begin
              if(rb2cf_C0RxRdValid) // read response received
                next_state = CALC;
            end
            CALC:
            begin
              if(integer_counter == 'd16 && cache_line_counter == cr_data_size)
                next_state = WRITE;
              if(integer_counter == 'd16 && cache_line_counter != cr_data_size)
                next_state = IDLE;
            end
            WRITE:
            begin
              if(!ci2cf_C1TxAlmFull) // write request sent
                next_state = DONE;
            end
        endcase
    end

    always @ (*) 
    begin
        cache_line_counter_d = cache_line_counter;
        integer_counter_d    = integer_counter;
        final_result_d       = final_result;
        RdHdr_valid          = 'b0;
        RdAddrOffset         = 'b0;
        RdReqId              = 'b0;
        WrHdr_valid          = 'b0;
        WrAddrOffset         = 'b0;
        WrReqId              = 'b0;
        WrData               = 'b0;
        task_completed_d     = 'b0;
        case(cur_state)                             /* synthesis parallel_case */
            IDLE:
            begin
              RdHdr_valid    = 'b1;
              RdAddrOffset   = cache_line_counter;
              RdReqId        = 'b0; // fixed ID for sequential kernel
            end
            WAIT:
            begin
              if(rb2cf_C0RxRdValid) // read response received
              begin
                cache_line_counter_d = cache_line_counter + 'b1;  // increment cache line counter
                integer_counter_d    = 'd16;                       // reset integer counter
              end
            end
            CALC:
            begin
              if(integer_counter != 'd16)
              begin
                integer_counter_d = integer_counter + 'b1;
              end
              else
              begin
                final_result_d = final_result ^ RdData;
              end
            end
            WRITE:
            begin
              WrHdr_valid    = 'b1;
              WrAddrOffset   = 'b0;
              WrReqId        = 'b0;
              WrData         = final_result;
              if(!ci2cf_C1TxAlmFull) // write request sent
                task_completed_d = 'b1;
            end
        endcase
    end

    //-------------------------
    // Handle CCI Tx Channels
    //-------------------------
    // Format Read Header
    wire [31:0]             RdAddr  = cr_src_address ^ RdAddrOffset;
    wire [TXHDR_WIDTH-1:0]  RdHdr   = {
                                        5'h00,                          // [60:56]      Byte Enable
                                        rdreq_type,                     // [55:52]      Request Type
                                        6'h00,                          // [51:46]      Rsvd
                                        RdAddr,                         // [45:14]      Address
                                        RdReqId                         // [13:0]       Meta data to track the SPL requests
                                      };
    
    // Format Write Header
    wire [31:0]             WrAddr  = cr_dst_address ^ WrAddrOffset;
    wire [TXHDR_WIDTH-1:0]  WrHdr   = {
                                        5'h00,                          // [60:56]      Byte Enable
                                        wrreq_type,                     // [55:52]      Request Type
                                        6'h00,                          // [51:46]      Rsvd
                                        WrAddr,                         // [45:14]      Address
                                        WrReqId                         // [13:0]       Meta data to track the SPL requests
                                      };

    // Sending Requests
    always @(posedge clk)
    begin

        if(!reset_n)
        begin
            afuid_updtd             <= 'b0;
            cf2ci_C1TxHdr           <= 'b0;
            cf2ci_C1TxWrValid       <= 'b0;
            cf2ci_C1TxData          <= 'b0;
            cf2ci_C0TxHdr           <= 'b0;
            cf2ci_C0TxRdValid       <= 'b0;
            dsm_base_valid_q        <= 'b0;
            task_completed          <= 'b0;
        end
        else
        begin 
            //Tx Path
            //--------------------------------------------------------------------------
            cf2ci_C1TxHdr           <= 'b0;
            cf2ci_C1TxWrValid       <= 'b0;
            cf2ci_C1TxData          <= 'b0;
            cf2ci_C0TxHdr           <= 'b0;
            cf2ci_C0TxRdValid       <= 'b0;
            dsm_base_valid_q        <= dsm_base_valid;
            task_completed          <= task_completed_d;

            // Channel 1
            if(ci2cf_C1TxAlmFull==0)
            begin
                //The first write request should be DSM initialization
                if( ci2cf_InitDn && dsm_base_valid_q && !afuid_updtd )
                begin
                    afuid_updtd             <= 1;
                    cf2ci_C1TxHdr           <= {
                                                    5'h0,                      // [60:56]      Byte Enable
                                                    WrLine,                    // [55:52]      Request Type
                                                    6'h00,                     // [51:46]      Rsvd
                                                    ds_afuid_address,          // [44:14]      Address
                                                    14'h3ffe                   // [13:0]       Meta data to track the SPL requests
                                               };                
                    cf2ci_C1TxWrValid       <= 1;
                    cf2ci_C1TxData          <= {    368'h0,                    // [512:144]    Zeros
                                                    VERSION ,                  // [143:128]    Version #2
                                                    MICRO_BENCH                 // [127:0]      AFU ID
                                               };
                end
                else if (re2xy_go)  //Executing real tasks
                begin
                    if(task_completed == 'b1) 
                    begin
                        cf2ci_C1TxWrValid   <= 1'b1;
                        cf2ci_C1TxHdr       <= {
                                                    5'h0,
                                                    WrLine,
                                                    6'h00,
                                                    ds_stat_address,
                                                    14'h3fff
                                               };
                        cf2ci_C1TxData      <= 'b1; // task completed
                    end
                    else if( WrHdr_valid )                                          // Write to Destination Workspace
                    begin                                                               
                        cf2ci_C1TxHdr     <= WrHdr;
                        cf2ci_C1TxWrValid <= 1'b1;
                        cf2ci_C1TxData    <= WrData;
                    end
                end // re2xy_go
            end // C1_TxAmlFull

            // Channel 0
            if(  re2xy_go 
              && RdHdr_valid && !ci2cf_C0TxAlmFull )                                // Read from Source Workspace
            begin                                                                   //----------------------------------
                cf2ci_C0TxHdr      <= RdHdr;
                cf2ci_C0TxRdValid  <= 'b1;
            end

            /* synthesis translate_off */
            if(cf2ci_C1TxWrValid)
                $display("*Req Type: %x \t Addr: %x \n Data: %x", cf2ci_C1TxHdr[55:52], cf2ci_C1TxHdr[45:14], cf2ci_C1TxData);

            if(cf2ci_C0TxRdValid)
                $display("*Req Type: %x \t Addr: %x", cf2ci_C0TxHdr[55:52], cf2ci_C0TxHdr[45:14]);

            /* synthesis translate_on */

        end
    end

    //-------------------------
    //Handle Responses
    //-------------------------

    //We have already handled Cfg Responses in the Configuration Mode
    //We do not need to care about Write Responses
    //Only Read Responses are considered
    always @ (posedge clk) 
    begin
        if (!reset_n)
        begin
          RdData <= 'b0;
        end
        else
        begin
          if (rb2cf_C0RxRdValid)
            RdData <= rb2cf_C0RxData;
        end
    end

    // Function: Returns physical address for a DSM register
    function automatic [31:0] dsm_offset2addr;
        input    [9:0]  offset_b;
        input    [63:0] base_b;
        begin
            dsm_offset2addr = base_b[37:6] + offset_b[9:6];
        end
    endfunction


endmodule

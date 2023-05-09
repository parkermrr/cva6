// Copyright 2018 - 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 08.02.2018
// Migrated: Luis Vitorio Cargnini, IEEE
// Date: 09.06.2018

// branch history table - 2 bit saturation counter
module bht #(
    parameter int unsigned NR_ENTRIES = 1024
)(
    input  logic                        clk_i,
    input  logic                        rst_ni,
    input  logic                        flush_i,
    input  logic                        debug_mode_i,
    input  logic [riscv::VLEN-1:0]      vpc_i,
    input  ariane_pkg::bht_update_t     bht_update_i,
    // we potentially need INSTR_PER_FETCH predictions/cycle
    output ariane_pkg::bht_prediction_t bht_prediction_o
);
    localparam INDEX_BITS = $clog2(NR_ENTRIES);

    struct packed {
        logic       valid;
        logic [1:0] saturation_counter;
    } bht_d[NR_ENTRIES-1:0], bht_q[NR_ENTRIES-1:0];

    logic [INDEX_BITS-1:0]  pred_index, update_index;
    logic [1:0]             curr_saturation_counter;
    logic [INDEX_BITS-1:0]  ghr;
    logic latest_taken;

    // gshare to find indices for next prediction and next update
    assign latest_taken = bht_update_i.taken;
    assign update_index = ghr ^ bht_update_i.pc[INDEX_BITS - 1:0];
    assign pred_index = ghr ^ vpc_i[INDEX_BITS - 1:0];

    // prediction assignment
    assign bht_prediction_o.valid = bht_q[pred_index].valid;
    assign bht_prediction_o.taken = bht_q[pred_index].saturation_counter[1] == 1'b1;

    always_comb begin : update_bht
        bht_d = bht_q;
        ghr = {ghr[INDEX_BITS-2:0], latest_taken};
        curr_saturation_counter = bht_q[update_index].saturation_counter;

        if (bht_update_i.valid && !debug_mode_i) begin
            bht_d[update_index].valid = 1'b1;
            if (curr_saturation_counter == 2'b11) begin
                if (!bht_update_i.taken)
                    bht_d[update_index].saturation_counter = curr_saturation_counter - 1;
            end else if (curr_saturation_counter == 2'b00) begin
                if (bht_update_i.taken)
                    bht_d[update_index].saturation_counter = curr_saturation_counter + 1;
            end else begin
                if (bht_update_i.taken)
                    bht_d[update_index].saturation_counter = curr_saturation_counter + 1;
                else
                    bht_d[update_index].saturation_counter = curr_saturation_counter - 1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int unsigned i = 0; i < NR_ENTRIES; i++) begin               
                bht_q[i] <= '0;
            end
            for (int unsigned i = 0; i < INDEX_BITS; i++) begin
                ghr[i] <= '0;
            end
        end else begin
            if (flush_i) begin
                for (int i = 0; i < NR_ENTRIES; i++) begin
                    bht_q[i].valid <=  1'b0;
                    bht_q[i].saturation_counter <= 2'b10;
                end
                for (int unsigned i = 0; i < INDEX_BITS; i++) begin
                    ghr[i] <= '0;
                end
            end else begin
                bht_q <= bht_d;
            end
        end
    end
endmodule

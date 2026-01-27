import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.handle import Immediate

class Testbench:
    def __init__(self, dut):
        self.dut = dut
        self.clk = dut.clk_i
        self.rst = dut.rst_ni
        
        self.clk.value = Immediate(0)
        self.rst.value = Immediate(1)

        cocotb.start_soon(Clock(self.clk, 10, 'ns').start())
        cocotb.start_soon(self.char_monitor())

    # Monitor for characters
    async def char_monitor(self):
        output = []
        while True:
            await RisingEdge(self.dut.sim_char_valid_o)
            char = chr(int(self.dut.sim_char_data_o.value))
            output.append(char)
            if char == '\n':
                self.dut._log.info("".join(output).rstrip())
                output.clear()


    # Wait for halt signal
    async def wait_on_finish(self):
        await RisingEdge(self.dut.sim_halt_o)
        self.dut._log.info("Test completed successfully")


    async def cycles(self, value: int):
        await ClockCycles(self.clk, value)


    async def reset(self):
        await self.cycles(2)
        self.rst.value = 0
        await self.cycles(5)
        self.rst.value = 1


@cocotb.test(timeout_time=1, timeout_unit='ms')
async def test_bringup(dut):
    tb = Testbench(dut)
    await tb.reset()
    await tb.cycles(10000)


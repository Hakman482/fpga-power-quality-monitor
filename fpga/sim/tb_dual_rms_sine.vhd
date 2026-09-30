library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;


entity tb_dual_rms_sine is
end entity tb_dual_rms_sine;


architecture simulation of tb_dual_rms_sine is

    ------------------------------------------------------------------
    -- FPGA clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Actual project parameters
    ------------------------------------------------------------------

    constant SAMPLE_RATE_HZ : integer := 10000;
    constant SIGNAL_FREQ_HZ : integer := 50;

    constant WINDOW_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- Test sine-wave peak amplitudes
    ------------------------------------------------------------------

    constant VOLTAGE_PEAK_MV : integer := 325000;

    constant CURRENT_PEAK_UA : integer := 1000000;


    ------------------------------------------------------------------
    -- Theoretical RMS values
    ------------------------------------------------------------------

    constant EXPECTED_VRMS_MV : integer := 229810;

    constant EXPECTED_IRMS_UA : integer := 707107;


    ------------------------------------------------------------------
    -- Allow small quantisation / integer-sqrt tolerance
    ------------------------------------------------------------------

    constant VOLTAGE_TOLERANCE_MV : integer := 10;

    constant CURRENT_TOLERANCE_UA : integer := 20;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';

    signal reset : std_logic := '1';


    signal voltage_mV_in : signed(31 downto 0)
                         := (others => '0');

    signal current_uA_in : signed(31 downto 0)
                         := (others => '0');


    signal sample_valid_in : std_logic := '0';


    signal voltage_rms_mV : unsigned(31 downto 0);

    signal current_rms_uA : unsigned(31 downto 0);

    signal rms_valid : std_logic;


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------

    signal sim_done : boolean := false;


begin


    ------------------------------------------------------------------
    -- 100 MHz FPGA clock
    ------------------------------------------------------------------

    clock_process : process

    begin

        while not sim_done loop

            clk_100mhz <= '0';

            wait for CLK_PERIOD / 2;

            clk_100mhz <= '1';

            wait for CLK_PERIOD / 2;

        end loop;


        clk_100mhz <= '0';

        wait;

    end process;



    ------------------------------------------------------------------
    -- Real 200-sample RMS block
    ------------------------------------------------------------------

    DUT : entity work.dual_rms

        generic map (

            WINDOW_SAMPLES => WINDOW_SAMPLES

        )

        port map (

            clk_100mhz => clk_100mhz,

            reset => reset,


            voltage_mV_in => voltage_mV_in,

            current_uA_in => current_uA_in,


            sample_valid_in => sample_valid_in,


            voltage_rms_mV => voltage_rms_mV,

            current_rms_uA => current_rms_uA,


            rms_valid => rms_valid

        );



    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------

    stimulus_process : process


        variable angle : real;

        variable voltage_real : real;

        variable current_real : real;

        variable voltage_integer : integer;

        variable current_integer : integer;

        variable voltage_error : integer;

        variable current_error : integer;


    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------

        reset <= '1';

        sample_valid_in <= '0';

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- Generate exactly 200 samples of one 50 Hz sine cycle
        --
        -- angle(n) =
        --
        -- 2*pi*n / 200
        ----------------------------------------------------------------

        for sample_index in 0 to WINDOW_SAMPLES - 1 loop


            ------------------------------------------------------------
            -- Calculate sine-wave phase
            ------------------------------------------------------------

            angle :=
                2.0 * math_pi *
                real(sample_index) /
                real(WINDOW_SAMPLES);


            ------------------------------------------------------------
            -- Voltage sine wave
            ------------------------------------------------------------

            voltage_real :=
                real(VOLTAGE_PEAK_MV) *
                sin(angle);


            ------------------------------------------------------------
            -- Current sine wave
            --
            -- Same phase for this test.
            ------------------------------------------------------------

            current_real :=
                real(CURRENT_PEAK_UA) *
                sin(angle);


            ------------------------------------------------------------
            -- Convert real simulation values to integers
            ------------------------------------------------------------

            voltage_integer :=
                integer(round(voltage_real));


            current_integer :=
                integer(round(current_real));


            ------------------------------------------------------------
            -- Apply sample
            ------------------------------------------------------------

            voltage_mV_in <=
                to_signed(
                    voltage_integer,
                    voltage_mV_in'length
                );


            current_uA_in <=
                to_signed(
                    current_integer,
                    current_uA_in'length
                );


            ------------------------------------------------------------
            -- Generate one valid pulse
            ------------------------------------------------------------

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '1';


            wait until rising_edge(clk_100mhz);

            wait until falling_edge(clk_100mhz);

            sample_valid_in <= '0';


            ------------------------------------------------------------
            -- Represent 10 kS/s spacing.
            --
            -- Real sample interval:
            --
            -- 100 us
            --
            -- Most of this delay is irrelevant to RMS arithmetic,
            -- but using it makes the simulation reflect the actual
            -- project timing.
            ------------------------------------------------------------

            wait for 99980 ns;


        end loop;



        ----------------------------------------------------------------
        -- Wait for RMS result
        ----------------------------------------------------------------

        if rms_valid /= '1' then

            wait until rising_edge(rms_valid);

        end if;


        wait for 1 ns;



        ----------------------------------------------------------------
        -- Calculate errors
        ----------------------------------------------------------------

        voltage_error :=
            abs(
                to_integer(voltage_rms_mV)
                -
                EXPECTED_VRMS_MV
            );


        current_error :=
            abs(
                to_integer(current_rms_uA)
                -
                EXPECTED_IRMS_UA
            );



        ----------------------------------------------------------------
        -- Voltage RMS check
        ----------------------------------------------------------------

        assert voltage_error <= VOLTAGE_TOLERANCE_MV

            report
                "50HZ SINE VOLTAGE RMS FAIL: expected approximately " &
                integer'image(EXPECTED_VRMS_MV) &
                " mV, received " &
                integer'image(to_integer(voltage_rms_mV)) &
                " mV"

            severity error;



        ----------------------------------------------------------------
        -- Current RMS check
        ----------------------------------------------------------------

        assert current_error <= CURRENT_TOLERANCE_UA

            report
                "50HZ SINE CURRENT RMS FAIL: expected approximately " &
                integer'image(EXPECTED_IRMS_UA) &
                " uA, received " &
                integer'image(to_integer(current_rms_uA)) &
                " uA"

            severity error;



        ----------------------------------------------------------------
        -- PASS report
        ----------------------------------------------------------------

        report
            "50HZ SINE RMS PASS: Vrms=" &
            integer'image(to_integer(voltage_rms_mV)) &
            " mV, Irms=" &
            integer'image(to_integer(current_rms_uA)) &
            " uA"

        severity note;



        report
            "=============================================="
        severity note;


        report
            "200-SAMPLE 50HZ RMS TEST COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        ----------------------------------------------------------------
        -- Stop simulation clock
        ----------------------------------------------------------------

        sim_done <= true;

        wait;


    end process;


end architecture simulation;
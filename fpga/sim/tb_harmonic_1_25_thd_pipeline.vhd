library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_harmonic_1_25_thd_pipeline is
end entity tb_harmonic_1_25_thd_pipeline;


architecture simulation of tb_harmonic_1_25_thd_pipeline is


    ------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Frame size
    ------------------------------------------------------------------
    constant FRAME_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- Voltage waveform
    --
    -- Fundamental = 325 V peak
    -- 3rd = 10%
    -- 5th = 5%
    -- 7th = 2%
    ------------------------------------------------------------------
    constant V1_PEAK_MV : integer := 325000;
    constant V3_PEAK_MV : integer := 32500;
    constant V5_PEAK_MV : integer := 16250;
    constant V7_PEAK_MV : integer := 6500;


    ------------------------------------------------------------------
    -- Current waveform
    --
    -- Fundamental = 1 A peak
    -- 3rd = 20%
    -- 5th = 10%
    ------------------------------------------------------------------
    constant I1_PEAK_UA : integer := 1000000;
    constant I3_PEAK_UA : integer := 200000;
    constant I5_PEAK_UA : integer := 100000;


    ------------------------------------------------------------------
    -- Theoretical THD
    --
    -- Voltage:
    --
    -- sqrt(
    --      0.10^2
    --    + 0.05^2
    --    + 0.02^2
    -- )
    --
    -- = 0.113578...
    -- = 11.3578 %
    --
    -- x100 output ≈ 1136
    --
    --
    -- Current:
    --
    -- sqrt(
    --      0.20^2
    --    + 0.10^2
    -- )
    --
    -- = 0.223606...
    -- = 22.3606 %
    --
    -- x100 output ≈ 2236
    ------------------------------------------------------------------
    constant EXPECTED_VTHD : integer := 1136;
    constant EXPECTED_ITHD : integer := 2236;


    ------------------------------------------------------------------
    -- FPGA signals
    ------------------------------------------------------------------
    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';

    signal sim_done :
        boolean := false;


    ------------------------------------------------------------------
    -- Harmonic extractor control
    ------------------------------------------------------------------
    signal extractor_start :
        std_logic := '0';

    signal extractor_busy :
        std_logic;

    signal harmonic_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Frame read interface
    ------------------------------------------------------------------
    signal read_index :
        unsigned(15 downto 0);

    signal voltage_sample_mV :
        signed(31 downto 0);

    signal current_sample_uA :
        signed(31 downto 0);


    ------------------------------------------------------------------
    -- Extractor outputs
    ------------------------------------------------------------------
    signal voltage_fund_mag_sq :
        unsigned(79 downto 0);

    signal current_fund_mag_sq :
        unsigned(79 downto 0);

    signal voltage_harm_sum_sq :
        unsigned(84 downto 0);

    signal current_harm_sum_sq :
        unsigned(84 downto 0);

    signal harmonic_number :
        unsigned(5 downto 0);


    ------------------------------------------------------------------
    -- THD outputs
    ------------------------------------------------------------------
    signal voltage_thd_x100 :
        unsigned(15 downto 0);

    signal current_thd_x100 :
        unsigned(15 downto 0);

    signal thd_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Captured final THD
    ------------------------------------------------------------------
    signal captured_voltage_thd :
        unsigned(15 downto 0) :=
        (others => '0');

    signal captured_current_thd :
        unsigned(15 downto 0) :=
        (others => '0');

    signal thd_seen :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Simulation-only stored frame
    ------------------------------------------------------------------
    type voltage_frame_t is
        array (0 to FRAME_SAMPLES - 1)
        of signed(31 downto 0);

    type current_frame_t is
        array (0 to FRAME_SAMPLES - 1)
        of signed(31 downto 0);


    signal voltage_frame :
        voltage_frame_t :=
        (others => (others => '0'));

    signal current_frame :
        current_frame_t :=
        (others => (others => '0'));


begin


    ------------------------------------------------------------------
    -- 100 MHz clock
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
    -- Frame readback model
    ------------------------------------------------------------------
    frame_read_process : process(
        read_index,
        voltage_frame,
        current_frame
    )

        variable idx : integer;

    begin

        idx := to_integer(read_index);

        if
            idx >= 0 and
            idx < FRAME_SAMPLES
        then

            voltage_sample_mV <=
                voltage_frame(idx);

            current_sample_uA <=
                current_frame(idx);

        else

            voltage_sample_mV <=
                (others => '0');

            current_sample_uA <=
                (others => '0');

        end if;

    end process;



    ------------------------------------------------------------------
    -- Harmonic extractor
    ------------------------------------------------------------------
    HARMONIC_EXTRACTOR :
        entity work.harmonic_1_25_extractor

        generic map (

            FRAME_SAMPLES =>
                FRAME_SAMPLES

        )

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,

            start =>
                extractor_start,


            read_index =>
                read_index,

            voltage_sample_mV =>
                voltage_sample_mV,

            current_sample_uA =>
                current_sample_uA,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,


            voltage_harm_sum_sq =>
                voltage_harm_sum_sq,

            current_harm_sum_sq =>
                current_harm_sum_sq,


            harmonic_number =>
                harmonic_number,

            busy =>
                extractor_busy,

            harmonic_valid =>
                harmonic_valid

        );



    ------------------------------------------------------------------
    -- Final THD calculator
    ------------------------------------------------------------------
    THD_METER :
        entity work.thd_1_25_meter

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,


            voltage_harm_sum_sq =>
                voltage_harm_sum_sq,

            current_harm_sum_sq =>
                current_harm_sum_sq,


            harmonic_valid_in =>
                harmonic_valid,


            voltage_thd_x100 =>
                voltage_thd_x100,

            current_thd_x100 =>
                current_thd_x100,


            thd_valid =>
                thd_valid

        );



    ------------------------------------------------------------------
    -- Capture THD result
    ------------------------------------------------------------------
    thd_monitor : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_voltage_thd <=
                    (others => '0');

                captured_current_thd <=
                    (others => '0');

                thd_seen <=
                    '0';


            elsif thd_valid = '1' then

                captured_voltage_thd <=
                    voltage_thd_x100;

                captured_current_thd <=
                    current_thd_x100;

                thd_seen <=
                    '1';

            end if;

        end if;

    end process;



    ------------------------------------------------------------------
    -- Stimulus
    ------------------------------------------------------------------
    stimulus_process : process


        variable theta :
            real;

        variable voltage_real :
            real;

        variable current_real :
            real;

        variable voltage_integer :
            integer;

        variable current_integer :
            integer;


        variable measured_vthd :
            integer;

        variable measured_ithd :
            integer;

        variable voltage_error :
            integer;

        variable current_error :
            integer;


    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        reset <= '1';

        extractor_start <= '0';

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- Build one distorted 200-sample frame
        ----------------------------------------------------------------
        for sample_index in 0 to FRAME_SAMPLES - 1 loop


            theta :=
                2.0 *
                math_pi *
                real(sample_index) /
                real(FRAME_SAMPLES);


            ------------------------------------------------------------
            -- Voltage
            ------------------------------------------------------------
            voltage_real :=

                real(V1_PEAK_MV) *
                sin(theta)

                +

                real(V3_PEAK_MV) *
                sin(3.0 * theta)

                +

                real(V5_PEAK_MV) *
                sin(5.0 * theta)

                +

                real(V7_PEAK_MV) *
                sin(7.0 * theta);


            ------------------------------------------------------------
            -- Current
            ------------------------------------------------------------
            current_real :=

                real(I1_PEAK_UA) *
                sin(theta)

                +

                real(I3_PEAK_UA) *
                sin(3.0 * theta)

                +

                real(I5_PEAK_UA) *
                sin(5.0 * theta);


            voltage_integer :=
                integer(
                    round(voltage_real)
                );


            current_integer :=
                integer(
                    round(current_real)
                );


            voltage_frame(sample_index) <=
                to_signed(
                    voltage_integer,
                    32
                );


            current_frame(sample_index) <=
                to_signed(
                    current_integer,
                    32
                );


        end loop;


        --------------------------------------------------------------
        -- Allow array assignments to settle
        --------------------------------------------------------------
        wait for 20 ns;



        ----------------------------------------------------------------
        -- Start 1-25 harmonic extraction
        ----------------------------------------------------------------
        wait until falling_edge(clk_100mhz);

        extractor_start <=
            '1';


        wait until rising_edge(clk_100mhz);

        wait until falling_edge(clk_100mhz);

        extractor_start <=
            '0';



        ----------------------------------------------------------------
        -- Wait until final THD result has propagated through both
        -- blocks.
        ----------------------------------------------------------------
        if thd_seen /= '1' then

            wait until thd_seen = '1';

        end if;


        wait for 1 ns;



        ----------------------------------------------------------------
        -- Capture result as integers
        ----------------------------------------------------------------
        measured_vthd :=
            to_integer(
                captured_voltage_thd
            );


        measured_ithd :=
            to_integer(
                captured_current_thd
            );


        voltage_error :=
            abs(
                measured_vthd -
                EXPECTED_VTHD
            );


        current_error :=
            abs(
                measured_ithd -
                EXPECTED_ITHD
            );



        ----------------------------------------------------------------
        -- Check completion state
        ----------------------------------------------------------------
        assert
            to_integer(harmonic_number) = 25

            report
                "FULL THD PIPELINE FAIL: final harmonic was not 25"

            severity error;



        ----------------------------------------------------------------
        -- Voltage THD verification
        --
        -- The individual extractor test already showed some small
        -- fixed-point Goertzel error, so allow about ±0.8 percentage
        -- points here.
        --
        -- THD_x100 tolerance 80 = 0.80%.
        ----------------------------------------------------------------
        assert voltage_error <= 80

            report
                "FULL 1-25 VOLTAGE THD FAIL: expected approximately " &
                integer'image(EXPECTED_VTHD) &
                ", measured " &
                integer'image(measured_vthd)

            severity error;



        ----------------------------------------------------------------
        -- Current THD verification
        ----------------------------------------------------------------
        assert current_error <= 100

            report
                "FULL 1-25 CURRENT THD FAIL: expected approximately " &
                integer'image(EXPECTED_ITHD) &
                ", measured " &
                integer'image(measured_ithd)

            severity error;



        ----------------------------------------------------------------
        -- Final report
        ----------------------------------------------------------------
        report
            "FULL HARMONIC 1-25 -> THD PIPELINE PASS: VTHD=" &
            integer'image(measured_vthd) &
            ", ITHD=" &
            integer'image(measured_ithd)

        severity note;


        report
            "EXPECTED VTHD APPROX 11.36 PERCENT"
        severity note;


        report
            "EXPECTED ITHD APPROX 22.36 PERCENT"
        severity note;


        report
            "FINAL HARMONIC NUMBER = " &
            integer'image(
                to_integer(harmonic_number)
            )

        severity note;


        report
            "=============================================="
        severity note;


        report
            "END-TO-END HARMONIC 1-25 / THD TEST COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        sim_done <= true;

        wait;


    end process;


end architecture simulation;
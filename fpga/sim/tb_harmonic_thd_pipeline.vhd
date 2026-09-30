library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_harmonic_thd_pipeline is
end entity tb_harmonic_thd_pipeline;


architecture simulation of tb_harmonic_thd_pipeline is


    ------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Frame size
    ------------------------------------------------------------------

    constant FRAME_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- Synthetic waveform amplitudes
    ------------------------------------------------------------------

    constant V1_PEAK_MV : integer := 325000;
    constant V3_PEAK_MV : integer := 32500;

    constant I1_PEAK_UA : integer := 1000000;
    constant I3_PEAK_UA : integer := 200000;


    ------------------------------------------------------------------
    -- Expected THD results
    --
    -- percent x100
    --
    -- 1000 = 10.00%
    -- 2000 = 20.00%
    ------------------------------------------------------------------

    constant EXPECTED_VTHD : integer := 1000;
    constant EXPECTED_ITHD : integer := 2000;


    ------------------------------------------------------------------
    -- Clock / reset
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

    signal harmonic_start :
        std_logic := '0';

    signal harmonic_busy :
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
    -- Harmonic results
    ------------------------------------------------------------------

    signal voltage_fund_mag_sq :
        unsigned(79 downto 0);

    signal voltage_3rd_mag_sq :
        unsigned(79 downto 0);

    signal current_fund_mag_sq :
        unsigned(79 downto 0);

    signal current_3rd_mag_sq :
        unsigned(79 downto 0);


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
    -- Simulation-only sample frame
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
    -- Frame readback
    --
    -- Models the output of sample_frame_buffer.
    ------------------------------------------------------------------

    frame_read_process : process(
        read_index,
        voltage_frame,
        current_frame
    )

        variable idx :
            integer;

    begin

        idx :=
            to_integer(read_index);


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
        entity work.harmonic_13_extractor

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
                harmonic_start,


            read_index =>
                read_index,

            voltage_sample_mV =>
                voltage_sample_mV,

            current_sample_uA =>
                current_sample_uA,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq,

            voltage_3rd_mag_sq =>
                voltage_3rd_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,

            current_3rd_mag_sq =>
                current_3rd_mag_sq,


            harmonic_valid =>
                harmonic_valid,

            busy =>
                harmonic_busy

        );



    ------------------------------------------------------------------
    -- THD meter
    ------------------------------------------------------------------

    THD_METER :
        entity work.thd_13_meter

        port map (

            clk_100mhz =>
                clk_100mhz,

            reset =>
                reset,


            voltage_fund_mag_sq =>
                voltage_fund_mag_sq,

            voltage_3rd_mag_sq =>
                voltage_3rd_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,

            current_3rd_mag_sq =>
                current_3rd_mag_sq,


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
    -- Capture final THD values
    ------------------------------------------------------------------

    thd_monitor : process(clk_100mhz)

    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                captured_voltage_thd <=
                    (others => '0');

                captured_current_thd <=
                    (others => '0');

                thd_seen <= '0';


            elsif thd_valid = '1' then

                captured_voltage_thd <=
                    voltage_thd_x100;

                captured_current_thd <=
                    current_thd_x100;

                thd_seen <= '1';

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

        variable v_error :
            integer;

        variable i_error :
            integer;


    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------

        reset <= '1';

        harmonic_start <= '0';

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- Build distorted 200-sample frame
        ----------------------------------------------------------------

        for sample_index in 0 to FRAME_SAMPLES - 1 loop


            theta :=
                2.0 *
                math_pi *
                real(sample_index) /
                real(FRAME_SAMPLES);


            ------------------------------------------------------------
            -- Voltage:
            --
            -- 325 V fundamental
            -- 32.5 V third harmonic
            --
            -- THD = 10%
            ------------------------------------------------------------

            voltage_real :=
                real(V1_PEAK_MV) *
                sin(theta)
                +
                real(V3_PEAK_MV) *
                sin(
                    3.0 * theta
                );


            ------------------------------------------------------------
            -- Current:
            --
            -- 1 A fundamental
            -- 0.2 A third harmonic
            --
            -- THD = 20%
            ------------------------------------------------------------

            current_real :=
                real(I1_PEAK_UA) *
                sin(theta)
                +
                real(I3_PEAK_UA) *
                sin(
                    3.0 * theta
                );


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
        -- Allow frame assignments to settle
        --------------------------------------------------------------

        wait for 20 ns;



        ----------------------------------------------------------------
        -- Start harmonic analysis
        ----------------------------------------------------------------

        wait until falling_edge(clk_100mhz);

        harmonic_start <= '1';


        wait until rising_edge(clk_100mhz);

        wait until falling_edge(clk_100mhz);

        harmonic_start <= '0';



        ----------------------------------------------------------------
        -- Wait for complete THD result
        ----------------------------------------------------------------

        if thd_seen /= '1' then

            wait until thd_seen = '1';

        end if;


        wait for 1 ns;



        ----------------------------------------------------------------
        -- Read results
        ----------------------------------------------------------------

        measured_vthd :=
            to_integer(
                captured_voltage_thd
            );


        measured_ithd :=
            to_integer(
                captured_current_thd
            );


        v_error :=
            abs(
                measured_vthd -
                EXPECTED_VTHD
            );


        i_error :=
            abs(
                measured_ithd -
                EXPECTED_ITHD
            );



        ----------------------------------------------------------------
        -- Voltage THD check
        --
        -- Allow ±3% relative approximately:
        --
        -- expected 1000
        -- tolerance 40 = 0.40 percentage points
        ----------------------------------------------------------------

        assert v_error <= 40

            report
                "HARMONIC-TO-THD VOLTAGE FAIL: expected approximately " &
                integer'image(EXPECTED_VTHD) &
                ", measured " &
                integer'image(measured_vthd)

            severity error;



        ----------------------------------------------------------------
        -- Current THD check
        ----------------------------------------------------------------

        assert i_error <= 50

            report
                "HARMONIC-TO-THD CURRENT FAIL: expected approximately " &
                integer'image(EXPECTED_ITHD) &
                ", measured " &
                integer'image(measured_ithd)

            severity error;



        ----------------------------------------------------------------
        -- PASS report
        ----------------------------------------------------------------

        report
            "HARMONIC -> THD PIPELINE PASS: VTHD=" &
            integer'image(measured_vthd) &
            ", ITHD=" &
            integer'image(measured_ithd)

        severity note;


        report
            "VOLTAGE THD = " &
            integer'image(measured_vthd / 100) &
            " percent approximately"

        severity note;


        report
            "CURRENT THD = " &
            integer'image(measured_ithd / 100) &
            " percent approximately"

        severity note;


        report
            "=============================================="
        severity note;


        report
            "END-TO-END HARMONIC/THD TEST COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        sim_done <= true;

        wait;


    end process;


end architecture simulation;
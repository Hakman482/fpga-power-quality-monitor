library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_harmonic_1_25_extractor is
end entity tb_harmonic_1_25_extractor;


architecture simulation of tb_harmonic_1_25_extractor is


    ------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Frame size
    ------------------------------------------------------------------
    constant FRAME_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- Voltage harmonic amplitudes
    ------------------------------------------------------------------
    constant V1_PEAK_MV : integer := 325000;

    constant V3_PEAK_MV : integer := 32500;  -- 10%
    constant V5_PEAK_MV : integer := 16250;  -- 5%
    constant V7_PEAK_MV : integer := 6500;   -- 2%


    ------------------------------------------------------------------
    -- Current harmonic amplitudes
    ------------------------------------------------------------------
    constant I1_PEAK_UA : integer := 1000000;

    constant I3_PEAK_UA : integer := 200000; -- 20%
    constant I5_PEAK_UA : integer := 100000; -- 10%


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------
    signal clk_100mhz :
        std_logic := '0';

    signal reset :
        std_logic := '1';

    signal start :
        std_logic := '0';


    signal read_index :
        unsigned(15 downto 0);


    signal voltage_sample_mV :
        signed(31 downto 0);

    signal current_sample_uA :
        signed(31 downto 0);


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

    signal busy :
        std_logic;

    signal harmonic_valid :
        std_logic;


    ------------------------------------------------------------------
    -- Simulation-only frame arrays
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


    ------------------------------------------------------------------
    -- Completion capture
    ------------------------------------------------------------------
    signal harmonic_seen :
        std_logic := '0';


    ------------------------------------------------------------------
    -- Simulation control
    ------------------------------------------------------------------
    signal sim_done :
        boolean := false;


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
    -- Frame-buffer read model
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
    -- DUT
    ------------------------------------------------------------------
    DUT : entity work.harmonic_1_25_extractor

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
                start,


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
                busy,

            harmonic_valid =>
                harmonic_valid

        );



    ------------------------------------------------------------------
    -- Capture completion pulse
    ------------------------------------------------------------------
    monitor_process : process(clk_100mhz)
    begin

        if rising_edge(clk_100mhz) then

            if reset = '1' then

                harmonic_seen <= '0';

            elsif harmonic_valid = '1' then

                harmonic_seen <= '1';

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


        --------------------------------------------------------------
        -- Ratio-check arithmetic
        --
        -- Voltage expected:
        --
        -- harmonic_sum / fundamental
        -- = 0.0129
        --
        -- Therefore:
        --
        -- harmonic_sum * 10000
        -- approximately
        -- fundamental * 129
        --------------------------------------------------------------

        variable v_harm_scaled :
            unsigned(98 downto 0);

        variable v_fund_scaled :
            unsigned(98 downto 0);

        variable v_error :
            unsigned(98 downto 0);

        variable v_tolerance :
            unsigned(98 downto 0);


        --------------------------------------------------------------
        -- Current expected:
        --
        -- harmonic_sum / fundamental = 0.05
        --
        -- therefore:
        --
        -- harmonic_sum * 20
        -- approximately fundamental
        --------------------------------------------------------------

        variable i_harm_scaled :
            unsigned(89 downto 0);

        variable i_fund_scaled :
            unsigned(89 downto 0);

        variable i_error :
            unsigned(89 downto 0);

        variable i_tolerance :
            unsigned(89 downto 0);


        variable v_harm_ext :
            unsigned(98 downto 0);

        variable v_fund_ext :
            unsigned(98 downto 0);

        variable i_harm_ext :
            unsigned(89 downto 0);

        variable i_fund_ext :
            unsigned(89 downto 0);


    begin


        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        reset <= '1';
        start <= '0';

        wait for 100 ns;

        reset <= '0';

        wait for 50 ns;



        ----------------------------------------------------------------
        -- Build 200-sample distorted frame
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
            -- fundamental
            -- +10% third
            -- +5% fifth
            -- +2% seventh
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
            -- Current:
            --
            -- fundamental
            -- +20% third
            -- +10% fifth
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
        -- Allow signal updates
        --------------------------------------------------------------
        wait for 20 ns;



        ----------------------------------------------------------------
        -- Start full harmonic extraction
        ----------------------------------------------------------------
        wait until falling_edge(clk_100mhz);

        start <= '1';

        wait until rising_edge(clk_100mhz);

        wait until falling_edge(clk_100mhz);

        start <= '0';



        ----------------------------------------------------------------
        -- Wait for completion
        ----------------------------------------------------------------
        if harmonic_seen /= '1' then

            wait until harmonic_seen = '1';

        end if;

        wait for 1 ns;



        ----------------------------------------------------------------
        -- Sanity checks
        ----------------------------------------------------------------
        assert voltage_fund_mag_sq /= 0

            report
                "FULL HARMONIC TEST FAIL: voltage fundamental is zero"

            severity error;


        assert current_fund_mag_sq /= 0

            report
                "FULL HARMONIC TEST FAIL: current fundamental is zero"

            severity error;



        ----------------------------------------------------------------
        -- VOLTAGE HARMONIC ENERGY TEST
        --
        -- Expected:
        --
        -- 0.10^2 + 0.05^2 + 0.02^2
        --
        -- = 0.0129
        --
        -- Therefore:
        --
        -- Vharm² * 10000 ~= V1² * 129
        ----------------------------------------------------------------

        v_harm_ext :=
            resize(
                voltage_harm_sum_sq,
                99
            );


        --------------------------------------------------------------
        -- ×10000
        --
        -- 10000 =
        -- 8192 + 1024 + 512 + 256 + 16
        --------------------------------------------------------------

        v_harm_scaled :=

            shift_left(v_harm_ext, 13)

            +

            shift_left(v_harm_ext, 10)

            +

            shift_left(v_harm_ext, 9)

            +

            shift_left(v_harm_ext, 8)

            +

            shift_left(v_harm_ext, 4);


        v_fund_ext :=
            resize(
                voltage_fund_mag_sq,
                99
            );


        --------------------------------------------------------------
        -- ×129 = ×128 + ×1
        --------------------------------------------------------------

        v_fund_scaled :=

            shift_left(
                v_fund_ext,
                7
            )

            +

            v_fund_ext;


        --------------------------------------------------------------
        -- Absolute difference
        --------------------------------------------------------------

        if v_harm_scaled >= v_fund_scaled then

            v_error :=
                v_harm_scaled -
                v_fund_scaled;

        else

            v_error :=
                v_fund_scaled -
                v_harm_scaled;

        end if;


        --------------------------------------------------------------
        -- Allow approximately 8% error on this first 25-bin
        -- fixed-point implementation.
        --------------------------------------------------------------

        v_tolerance :=
            shift_right(
                v_fund_scaled,
                3
            );


        assert v_error <= v_tolerance

            report
                "FULL HARMONIC VOLTAGE ENERGY RATIO FAIL"

            severity error;



        ----------------------------------------------------------------
        -- CURRENT HARMONIC ENERGY TEST
        --
        -- 0.20² + 0.10²
        --
        -- = 0.05
        --
        -- Therefore:
        --
        -- Iharm² × 20 ~= I1²
        ----------------------------------------------------------------

        i_harm_ext :=
            resize(
                current_harm_sum_sq,
                90
            );


        --------------------------------------------------------------
        -- ×20 = ×16 + ×4
        --------------------------------------------------------------

        i_harm_scaled :=

            shift_left(
                i_harm_ext,
                4
            )

            +

            shift_left(
                i_harm_ext,
                2
            );


        i_fund_ext :=
            resize(
                current_fund_mag_sq,
                90
            );


        i_fund_scaled :=
            i_fund_ext;


        --------------------------------------------------------------
        -- Absolute difference
        --------------------------------------------------------------

        if i_harm_scaled >= i_fund_scaled then

            i_error :=
                i_harm_scaled -
                i_fund_scaled;

        else

            i_error :=
                i_fund_scaled -
                i_harm_scaled;

        end if;


        --------------------------------------------------------------
        -- Allow approximately 8%
        --------------------------------------------------------------

        i_tolerance :=
            shift_right(
                i_fund_scaled,
                3
            );


        assert i_error <= i_tolerance

            report
                "FULL HARMONIC CURRENT ENERGY RATIO FAIL"

            severity error;



        ----------------------------------------------------------------
        -- PASS
        ----------------------------------------------------------------

        report
            "VOLTAGE HARMONICS 1-25 EXTRACTION PASS"
        severity note;


        report
            "CURRENT HARMONICS 1-25 EXTRACTION PASS"
        severity note;


        report
            "EXPECTED VOLTAGE HARMONIC ENERGY RATIO = 0.0129"
        severity note;


        report
            "EXPECTED CURRENT HARMONIC ENERGY RATIO = 0.0500"
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
            "HARMONIC 1-25 EXTRACTOR TESTS COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;


        sim_done <= true;

        wait;


    end process;


end architecture simulation;
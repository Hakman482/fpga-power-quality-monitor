library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;


entity tb_harmonic_13_extractor is
end entity tb_harmonic_13_extractor;


architecture simulation of tb_harmonic_13_extractor is


    ------------------------------------------------------------------
    -- Clock
    ------------------------------------------------------------------

    constant CLK_PERIOD : time := 10 ns;


    ------------------------------------------------------------------
    -- Frame
    ------------------------------------------------------------------

    constant FRAME_SAMPLES : integer := 200;


    ------------------------------------------------------------------
    -- Synthetic harmonic amplitudes
    ------------------------------------------------------------------

    constant V1_PEAK_MV : integer := 325000;
    constant V3_PEAK_MV : integer := 32500;

    constant I1_PEAK_UA : integer := 1000000;
    constant I3_PEAK_UA : integer := 200000;


    ------------------------------------------------------------------
    -- DUT signals
    ------------------------------------------------------------------

    signal clk_100mhz : std_logic := '0';
    signal reset      : std_logic := '1';

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

    signal voltage_3rd_mag_sq :
        unsigned(79 downto 0);

    signal current_fund_mag_sq :
        unsigned(79 downto 0);

    signal current_3rd_mag_sq :
        unsigned(79 downto 0);

    signal harmonic_valid :
        std_logic;

    signal busy :
        std_logic;


    ------------------------------------------------------------------
    -- Simulation-only frame storage
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
    -- Simulation control
    ------------------------------------------------------------------

    signal sim_done :
        boolean := false;


begin


    ------------------------------------------------------------------
    -- Clock
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
    -- Simulation frame readback
    --
    -- Models the sample_frame_buffer read interface.
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

    DUT : entity work.harmonic_13_extractor

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

            voltage_3rd_mag_sq =>
                voltage_3rd_mag_sq,

            current_fund_mag_sq =>
                current_fund_mag_sq,

            current_3rd_mag_sq =>
                current_3rd_mag_sq,

            harmonic_valid =>
                harmonic_valid,

            busy =>
                busy

        );



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


        ----------------------------------------------------------------
        -- Ratio-check arithmetic
        ----------------------------------------------------------------

        variable v3_extended :
            unsigned(87 downto 0);

        variable v3_times_100 :
            unsigned(87 downto 0);

        variable v1_extended :
            unsigned(87 downto 0);


        variable i3_extended :
            unsigned(84 downto 0);

        variable i3_times_25 :
            unsigned(84 downto 0);

        variable i1_extended :
            unsigned(84 downto 0);


        variable v_ratio_error :
            unsigned(87 downto 0);

        variable i_ratio_error :
            unsigned(84 downto 0);


        variable v_tolerance :
            unsigned(87 downto 0);

        variable i_tolerance :
            unsigned(84 downto 0);


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
        -- Build one 200-sample frame
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
            -- fundamental + 10% third harmonic
            ------------------------------------------------------------

            voltage_real :=
                real(V1_PEAK_MV) *
                sin(theta)
                +
                real(V3_PEAK_MV) *
                sin(3.0 * theta);


            ------------------------------------------------------------
            -- Current:
            --
            -- fundamental + 20% third harmonic
            ------------------------------------------------------------

            current_real :=
                real(I1_PEAK_UA) *
                sin(theta)
                +
                real(I3_PEAK_UA) *
                sin(3.0 * theta);


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
        -- Allow frame signals to update
        --------------------------------------------------------------

        wait for 20 ns;



        ----------------------------------------------------------------
        -- Start harmonic extraction
        ----------------------------------------------------------------

        wait until falling_edge(clk_100mhz);

        start <= '1';


        wait until rising_edge(clk_100mhz);

        wait until falling_edge(clk_100mhz);

        start <= '0';



        ----------------------------------------------------------------
        -- Wait for completion
        ----------------------------------------------------------------

        if harmonic_valid /= '1' then

            wait until rising_edge(harmonic_valid);

        end if;


        wait for 1 ns;



        ----------------------------------------------------------------
        -- Basic sanity checks
        ----------------------------------------------------------------

        assert voltage_fund_mag_sq /= 0

            report
                "VOLTAGE FUNDAMENTAL MAGNITUDE IS ZERO"

            severity error;


        assert current_fund_mag_sq /= 0

            report
                "CURRENT FUNDAMENTAL MAGNITUDE IS ZERO"

            severity error;



        ----------------------------------------------------------------
        -- VOLTAGE RATIO CHECK
        --
        -- V3 / V1 = 0.10
        --
        -- Therefore:
        --
        -- V3² / V1² = 0.01
        --
        -- Hence:
        --
        -- 100 * V3² ~= V1²
        ----------------------------------------------------------------

        v3_extended :=
            resize(
                voltage_3rd_mag_sq,
                88
            );


        --------------------------------------------------------------
        -- Multiply by 100 without width expansion:
        --
        -- 100 = 64 + 32 + 4
        --------------------------------------------------------------

        v3_times_100 :=
            shift_left(
                v3_extended,
                6
            )
            +
            shift_left(
                v3_extended,
                5
            )
            +
            shift_left(
                v3_extended,
                2
            );


        v1_extended :=
            resize(
                voltage_fund_mag_sq,
                88
            );


        --------------------------------------------------------------
        -- Absolute difference
        --------------------------------------------------------------

        if v3_times_100 >= v1_extended then

            v_ratio_error :=
                v3_times_100 -
                v1_extended;

        else

            v_ratio_error :=
                v1_extended -
                v3_times_100;

        end if;


        --------------------------------------------------------------
        -- Approx 3.125% tolerance:
        --
        -- fundamental / 32
        --------------------------------------------------------------

        v_tolerance :=
            shift_right(
                v1_extended,
                5
            );


        assert v_ratio_error <= v_tolerance

            report
                "VOLTAGE 3RD HARMONIC RATIO FAIL"

            severity error;



        ----------------------------------------------------------------
        -- CURRENT RATIO CHECK
        --
        -- I3 / I1 = 0.20
        --
        -- Therefore:
        --
        -- I3² / I1² = 0.04
        --
        -- Hence:
        --
        -- 25 * I3² ~= I1²
        ----------------------------------------------------------------

        i3_extended :=
            resize(
                current_3rd_mag_sq,
                85
            );


        --------------------------------------------------------------
        -- Multiply by 25 without width expansion:
        --
        -- 25 = 16 + 8 + 1
        --------------------------------------------------------------

        i3_times_25 :=
            shift_left(
                i3_extended,
                4
            )
            +
            shift_left(
                i3_extended,
                3
            )
            +
            i3_extended;


        i1_extended :=
            resize(
                current_fund_mag_sq,
                85
            );


        --------------------------------------------------------------
        -- Absolute difference
        --------------------------------------------------------------

        if i3_times_25 >= i1_extended then

            i_ratio_error :=
                i3_times_25 -
                i1_extended;

        else

            i_ratio_error :=
                i1_extended -
                i3_times_25;

        end if;


        --------------------------------------------------------------
        -- Approx 3.125% tolerance
        --------------------------------------------------------------

        i_tolerance :=
            shift_right(
                i1_extended,
                5
            );


        assert i_ratio_error <= i_tolerance

            report
                "CURRENT 3RD HARMONIC RATIO FAIL"

            severity error;



        ----------------------------------------------------------------
        -- PASS messages
        ----------------------------------------------------------------

        report
            "VOLTAGE FUNDAMENTAL + 3RD HARMONIC EXTRACTION PASS"
        severity note;


        report
            "CURRENT FUNDAMENTAL + 3RD HARMONIC EXTRACTION PASS"
        severity note;


        report
            "EXPECTED VOLTAGE V3/V1 = 0.10"
        severity note;


        report
            "EXPECTED CURRENT I3/I1 = 0.20"
        severity note;


        report
            "=============================================="
        severity note;


        report
            "HARMONIC 1/3 EXTRACTOR TESTS COMPLETED"
        severity note;


        report
            "=============================================="
        severity note;



        sim_done <= true;

        wait;


    end process;


end architecture simulation;
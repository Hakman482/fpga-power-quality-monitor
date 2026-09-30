library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity harmonic_13_extractor is

    generic (

        FRAME_SAMPLES : positive := 200

    );

    port (

        --------------------------------------------------------------
        -- FPGA system
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;


        --------------------------------------------------------------
        -- Start processing one complete frame
        --
        -- Connect later to frame_valid from sample_frame_buffer.
        --------------------------------------------------------------
        start : in std_logic;


        --------------------------------------------------------------
        -- Frame-buffer read interface
        --------------------------------------------------------------
        read_index :
            out unsigned(15 downto 0);

        voltage_sample_mV :
            in signed(31 downto 0);

        current_sample_uA :
            in signed(31 downto 0);


        --------------------------------------------------------------
        -- Goertzel magnitude squared:
        --
        -- fundamental = 50 Hz
        -- third       = 150 Hz
        --
        -- Magnitude-squared values are sufficient for the subsequent
        -- THD-ratio calculation.
        --------------------------------------------------------------
        voltage_fund_mag_sq :
            out unsigned(79 downto 0);

        voltage_3rd_mag_sq :
            out unsigned(79 downto 0);

        current_fund_mag_sq :
            out unsigned(79 downto 0);

        current_3rd_mag_sq :
            out unsigned(79 downto 0);


        --------------------------------------------------------------
        -- One-clock pulse when all four results are ready
        --------------------------------------------------------------
        harmonic_valid :
            out std_logic;


        --------------------------------------------------------------
        -- Processing status
        --------------------------------------------------------------
        busy :
            out std_logic

    );

end entity harmonic_13_extractor;



architecture rtl of harmonic_13_extractor is


    ------------------------------------------------------------------
    -- Fixed-point coefficient format:
    --
    -- Q2.14
    --
    -- coefficient = 2*cos(2*pi*k/N)
    --
    -- k = 1:
    -- 2*cos(2*pi/200) = 1.999013...
    --
    -- 1.999013 * 2^14 ≈ 32752
    --
    -- k = 3:
    -- 2*cos(6*pi/200) = 1.991124...
    --
    -- 1.991124 * 2^14 ≈ 32623
    ------------------------------------------------------------------

    constant COEFF_FUND :
        signed(15 downto 0) :=
        to_signed(32752, 16);

    constant COEFF_3RD :
        signed(15 downto 0) :=
        to_signed(32623, 16);

    constant COEFF_SHIFT :
        integer := 14;



    ------------------------------------------------------------------
    -- Goertzel state width
    --
    -- Wider than input samples to provide accumulation headroom.
    ------------------------------------------------------------------

    subtype state_t is signed(39 downto 0);



    ------------------------------------------------------------------
    -- Voltage fundamental states
    ------------------------------------------------------------------

    signal v1_s1 :
        state_t := (others => '0');

    signal v1_s2 :
        state_t := (others => '0');


    ------------------------------------------------------------------
    -- Voltage third-harmonic states
    ------------------------------------------------------------------

    signal v3_s1 :
        state_t := (others => '0');

    signal v3_s2 :
        state_t := (others => '0');


    ------------------------------------------------------------------
    -- Current fundamental states
    ------------------------------------------------------------------

    signal i1_s1 :
        state_t := (others => '0');

    signal i1_s2 :
        state_t := (others => '0');


    ------------------------------------------------------------------
    -- Current third-harmonic states
    ------------------------------------------------------------------

    signal i3_s1 :
        state_t := (others => '0');

    signal i3_s2 :
        state_t := (others => '0');



    ------------------------------------------------------------------
    -- Sample index
    ------------------------------------------------------------------

    signal sample_index :
        integer range 0 to FRAME_SAMPLES - 1 := 0;



    ------------------------------------------------------------------
    -- State machine
    ------------------------------------------------------------------

    type state_machine_t is (

        IDLE,
        PROCESS_FRAME,
        CALCULATE_MAGNITUDE,
        OUTPUT_RESULT

    );

    signal state :
        state_machine_t := IDLE;



    ------------------------------------------------------------------
    -- Function:
    -- one Goertzel recurrence
    --
    -- s0 =
    -- x
    -- + coefficient*s1
    -- - s2
    ------------------------------------------------------------------

    function goertzel_next (

        sample_in :
            signed(31 downto 0);

        s1 :
            state_t;

        s2 :
            state_t;

        coefficient :
            signed(15 downto 0)

    ) return state_t is


        variable product :
            signed(55 downto 0);

        variable scaled_product :
            state_t;

        variable result_value :
            state_t;


    begin


        --------------------------------------------------------------
        -- 40 × 16 = 56 bits
        --------------------------------------------------------------

        product :=
            s1 *
            coefficient;


        --------------------------------------------------------------
        -- Convert Q2.14 result back to integer scale
        --------------------------------------------------------------

        scaled_product :=
            resize(
                shift_right(
                    product,
                    COEFF_SHIFT
                ),
                state_t'length
            );


        --------------------------------------------------------------
        -- Goertzel recurrence
        --------------------------------------------------------------

        result_value :=
            resize(
                sample_in,
                state_t'length
            )
            +
            scaled_product
            -
            s2;


        return result_value;


    end function;



    ------------------------------------------------------------------
    -- Function:
    -- calculate Goertzel magnitude squared
    --
    -- |X[k]|² =
    --
    -- s1² + s2² - coeff*s1*s2
    ------------------------------------------------------------------

    function magnitude_squared (

        s1 :
            state_t;

        s2 :
            state_t;

        coefficient :
            signed(15 downto 0)

    ) return unsigned is


        variable s1_square :
            signed(79 downto 0);

        variable s2_square :
            signed(79 downto 0);

        variable cross_product :
            signed(79 downto 0);

        variable coeff_cross :
            signed(95 downto 0);

        variable coeff_cross_scaled :
            signed(79 downto 0);

        variable magnitude_value :
            signed(79 downto 0);


    begin


        --------------------------------------------------------------
        -- s1²
        --------------------------------------------------------------

        s1_square :=
            s1 * s1;


        --------------------------------------------------------------
        -- s2²
        --------------------------------------------------------------

        s2_square :=
            s2 * s2;


        --------------------------------------------------------------
        -- s1*s2
        --------------------------------------------------------------

        cross_product :=
            s1 * s2;


        --------------------------------------------------------------
        -- coefficient*s1*s2
        --
        -- 80 × 16 = 96 bits
        --------------------------------------------------------------

        coeff_cross :=
            cross_product *
            coefficient;


        --------------------------------------------------------------
        -- Remove Q2.14 coefficient scaling
        --------------------------------------------------------------

        coeff_cross_scaled :=
            resize(
                shift_right(
                    coeff_cross,
                    COEFF_SHIFT
                ),
                80
            );


        --------------------------------------------------------------
        -- Magnitude squared
        --------------------------------------------------------------

        magnitude_value :=
            s1_square
            +
            s2_square
            -
            coeff_cross_scaled;


        --------------------------------------------------------------
        -- Magnitude squared cannot physically be negative.
        --------------------------------------------------------------

        if magnitude_value < 0 then

            return to_unsigned(0, 80);

        else

            return unsigned(magnitude_value);

        end if;


    end function;



begin


    ------------------------------------------------------------------
    -- Read-index output
    ------------------------------------------------------------------

    read_index <=
        to_unsigned(
            sample_index,
            read_index'length
        );



    ------------------------------------------------------------------
    -- Main harmonic-processing state machine
    ------------------------------------------------------------------

    harmonic_process : process(clk_100mhz)


        variable new_v1 :
            state_t;

        variable new_v3 :
            state_t;

        variable new_i1 :
            state_t;

        variable new_i3 :
            state_t;


    begin


        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then


                state <= IDLE;

                sample_index <= 0;


                v1_s1 <= (others => '0');
                v1_s2 <= (others => '0');

                v3_s1 <= (others => '0');
                v3_s2 <= (others => '0');

                i1_s1 <= (others => '0');
                i1_s2 <= (others => '0');

                i3_s1 <= (others => '0');
                i3_s2 <= (others => '0');


                voltage_fund_mag_sq <=
                    (others => '0');

                voltage_3rd_mag_sq <=
                    (others => '0');

                current_fund_mag_sq <=
                    (others => '0');

                current_3rd_mag_sq <=
                    (others => '0');


                harmonic_valid <= '0';

                busy <= '0';



            else


                ------------------------------------------------------
                -- Default valid pulse
                ------------------------------------------------------

                harmonic_valid <= '0';



                case state is


                    --------------------------------------------------
                    -- IDLE
                    --------------------------------------------------

                    when IDLE =>


                        busy <= '0';


                        if start = '1' then


                            ------------------------------------------------
                            -- Clear previous Goertzel states
                            ------------------------------------------------

                            v1_s1 <= (others => '0');
                            v1_s2 <= (others => '0');

                            v3_s1 <= (others => '0');
                            v3_s2 <= (others => '0');

                            i1_s1 <= (others => '0');
                            i1_s2 <= (others => '0');

                            i3_s1 <= (others => '0');
                            i3_s2 <= (others => '0');


                            sample_index <= 0;

                            busy <= '1';

                            state <= PROCESS_FRAME;


                        end if;



                    --------------------------------------------------
                    -- PROCESS ALL 200 FRAME SAMPLES
                    --------------------------------------------------

                    when PROCESS_FRAME =>


                        busy <= '1';


                        ------------------------------------------------
                        -- Voltage fundamental
                        ------------------------------------------------

                        new_v1 :=
                            goertzel_next(

                                voltage_sample_mV,

                                v1_s1,

                                v1_s2,

                                COEFF_FUND

                            );


                        ------------------------------------------------
                        -- Voltage third harmonic
                        ------------------------------------------------

                        new_v3 :=
                            goertzel_next(

                                voltage_sample_mV,

                                v3_s1,

                                v3_s2,

                                COEFF_3RD

                            );


                        ------------------------------------------------
                        -- Current fundamental
                        ------------------------------------------------

                        new_i1 :=
                            goertzel_next(

                                current_sample_uA,

                                i1_s1,

                                i1_s2,

                                COEFF_FUND

                            );


                        ------------------------------------------------
                        -- Current third harmonic
                        ------------------------------------------------

                        new_i3 :=
                            goertzel_next(

                                current_sample_uA,

                                i3_s1,

                                i3_s2,

                                COEFF_3RD

                            );


                        ------------------------------------------------
                        -- Shift Goertzel states
                        ------------------------------------------------

                        v1_s2 <= v1_s1;
                        v1_s1 <= new_v1;

                        v3_s2 <= v3_s1;
                        v3_s1 <= new_v3;

                        i1_s2 <= i1_s1;
                        i1_s1 <= new_i1;

                        i3_s2 <= i3_s1;
                        i3_s1 <= new_i3;


                        ------------------------------------------------
                        -- End of frame?
                        ------------------------------------------------

                        if sample_index =
                           FRAME_SAMPLES - 1
                        then


                            state <=
                                CALCULATE_MAGNITUDE;


                        else


                            sample_index <=
                                sample_index + 1;


                        end if;



                    --------------------------------------------------
                    -- CALCULATE FOUR MAGNITUDE-SQUARED VALUES
                    --------------------------------------------------

                    when CALCULATE_MAGNITUDE =>


                        busy <= '1';


                        voltage_fund_mag_sq <=
                            magnitude_squared(

                                v1_s1,
                                v1_s2,
                                COEFF_FUND

                            );


                        voltage_3rd_mag_sq <=
                            magnitude_squared(

                                v3_s1,
                                v3_s2,
                                COEFF_3RD

                            );


                        current_fund_mag_sq <=
                            magnitude_squared(

                                i1_s1,
                                i1_s2,
                                COEFF_FUND

                            );


                        current_3rd_mag_sq <=
                            magnitude_squared(

                                i3_s1,
                                i3_s2,
                                COEFF_3RD

                            );


                        state <= OUTPUT_RESULT;



                    --------------------------------------------------
                    -- OUTPUT
                    --------------------------------------------------

                    when OUTPUT_RESULT =>


                        harmonic_valid <= '1';

                        busy <= '0';

                        state <= IDLE;



                end case;

            end if;

        end if;

    end process;


end architecture rtl;
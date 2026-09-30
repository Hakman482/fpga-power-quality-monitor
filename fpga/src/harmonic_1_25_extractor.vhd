library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity harmonic_1_25_extractor is

    generic (

        FRAME_SAMPLES :
            positive := 210

    );

    port (

        --------------------------------------------------------------
        -- FPGA
        --------------------------------------------------------------
        clk_100mhz :
            in std_logic;

        reset :
            in std_logic;


        --------------------------------------------------------------
        -- Start analysis of a newly completed electrical cycle
        --------------------------------------------------------------
        start :
            in std_logic;


        --------------------------------------------------------------
        -- Actual captured electrical-cycle length
        --------------------------------------------------------------
        frame_sample_count :
            in unsigned(15 downto 0);


        --------------------------------------------------------------
        -- Synchronous BRAM frame interface
        --------------------------------------------------------------
        read_index :
            out unsigned(15 downto 0);

        voltage_sample_mV :
            in signed(31 downto 0);

        current_sample_uA :
            in signed(31 downto 0);


        --------------------------------------------------------------
        -- Fundamental magnitude squared
        --------------------------------------------------------------
        voltage_fund_mag_sq :
            out unsigned(79 downto 0);

        current_fund_mag_sq :
            out unsigned(79 downto 0);


        --------------------------------------------------------------
        -- Sum of harmonic magnitudes squared, h = 2 ... 25
        --------------------------------------------------------------
        voltage_harm_sum_sq :
            out unsigned(84 downto 0);

        current_harm_sum_sq :
            out unsigned(84 downto 0);


        --------------------------------------------------------------
        -- Current harmonic being processed
        --------------------------------------------------------------
        harmonic_number :
            out unsigned(5 downto 0);


        busy :
            out std_logic;

        harmonic_valid :
            out std_logic

    );

end entity harmonic_1_25_extractor;



architecture rtl of harmonic_1_25_extractor is


    ------------------------------------------------------------------
    -- Goertzel coefficient fixed-point format
    --
    -- UPDATED:
    -- Q2.16 instead of Q2.14
    ------------------------------------------------------------------

    constant COEFF_SHIFT :
        integer := 16;



    ------------------------------------------------------------------
    -- Goertzel recurrence state width
    ------------------------------------------------------------------

    subtype state_value_t is
        signed(39 downto 0);



    ------------------------------------------------------------------
    -- Recurrence states
    ------------------------------------------------------------------

    signal voltage_s1 :
        state_value_t :=
        (others => '0');

    signal voltage_s2 :
        state_value_t :=
        (others => '0');


    signal current_s1 :
        state_value_t :=
        (others => '0');

    signal current_s2 :
        state_value_t :=
        (others => '0');



    ------------------------------------------------------------------
    -- BRAM read addressing
    ------------------------------------------------------------------

    signal read_index_reg :
        unsigned(15 downto 0) :=
        (others => '0');


    signal sample_index :
        integer range 0 to FRAME_SAMPLES - 1 :=
        0;


    signal frame_count_reg :
        integer range 190 to FRAME_SAMPLES :=
        200;



    ------------------------------------------------------------------
    -- Harmonic being processed
    ------------------------------------------------------------------

    signal harmonic_index :
        integer range 1 to 25 :=
        1;



    ------------------------------------------------------------------
    -- UPDATED:
    -- Q2.16 coefficient requires 18 signed bits
    ------------------------------------------------------------------

    signal coefficient_reg :
        signed(17 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- GOERTZEL RECURRENCE PIPELINE
    --
    -- 40-bit state x 18-bit coefficient = 58-bit product
    ------------------------------------------------------------------

    signal voltage_coeff_product_reg :
        signed(57 downto 0) :=
        (others => '0');


    signal current_coeff_product_reg :
        signed(57 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Sample and s2 delay registers
    ------------------------------------------------------------------

    signal voltage_sample_reg :
        signed(31 downto 0) :=
        (others => '0');


    signal current_sample_reg :
        signed(31 downto 0) :=
        (others => '0');


    signal voltage_s2_delay_reg :
        state_value_t :=
        (others => '0');


    signal current_s2_delay_reg :
        state_value_t :=
        (others => '0');



    ------------------------------------------------------------------
    -- Recurrence stage 2
    ------------------------------------------------------------------

    signal voltage_partial_sum_reg :
        state_value_t :=
        (others => '0');


    signal current_partial_sum_reg :
        state_value_t :=
        (others => '0');



    ------------------------------------------------------------------
    -- Recurrence stage 3 alignment
    ------------------------------------------------------------------

    signal voltage_s2_stage3_reg :
        state_value_t :=
        (others => '0');


    signal current_s2_stage3_reg :
        state_value_t :=
        (others => '0');



    ------------------------------------------------------------------
    -- Harmonic extraction results
    ------------------------------------------------------------------

    signal voltage_fundamental_int :
        unsigned(79 downto 0) :=
        (others => '0');


    signal current_fundamental_int :
        unsigned(79 downto 0) :=
        (others => '0');


    signal voltage_harmonic_sum_int :
        unsigned(84 downto 0) :=
        (others => '0');


    signal current_harmonic_sum_int :
        unsigned(84 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- Magnitude pipeline
    ------------------------------------------------------------------

    signal voltage_s1_square_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal voltage_s2_square_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal voltage_cross_reg :
        signed(79 downto 0) :=
        (others => '0');


    --------------------------------------------------------------
    -- UPDATED:
    -- 80-bit cross product x 18-bit coefficient = 98 bits
    --------------------------------------------------------------

    signal voltage_coeff_cross_reg :
        signed(97 downto 0) :=
        (others => '0');


    signal voltage_cross_scaled_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal voltage_mag_sq_reg :
        unsigned(79 downto 0) :=
        (others => '0');



    signal current_s1_square_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal current_s2_square_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal current_cross_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal current_coeff_cross_reg :
        signed(97 downto 0) :=
        (others => '0');


    signal current_cross_scaled_reg :
        signed(79 downto 0) :=
        (others => '0');


    signal current_mag_sq_reg :
        unsigned(79 downto 0) :=
        (others => '0');



    ------------------------------------------------------------------
    -- EXACT Q2.16 FREQUENCY-ADAPTIVE COEFFICIENT ROM
    --
    -- C(N,k) =
    --
    -- round(
    --     2*cos(2*pi*k/N) * 2^16
    -- )
    --
    -- N = 190 ... 210
    -- k = 1 ... 25
    ------------------------------------------------------------------

    type coefficient_row_t is
        array (1 to 25)
        of integer range -131072 to 131071;


    type coefficient_table_t is
        array (190 to 210)
        of coefficient_row_t;



    constant COEFFICIENT_TABLE :
        coefficient_table_t := (

        190 => (
            131000, 130785, 130428, 129927, 129284,
            128500, 127576, 126512, 125310, 123970,
            122495, 120886, 119145, 117274, 115274,
            113149, 110899, 108529, 106039, 103434,
            100716, 97887, 94952, 91913, 88773
        ),

        191 => (
            131001, 130788, 130434, 129939, 129303,
            128527, 127612, 126559, 125369, 124044,
            122584, 120991, 119268, 117416, 115436,
            113332, 111105, 108757, 106292, 103712,
            101020, 98219, 95311, 92300, 89189
        ),

        192 => (
            131002, 130791, 130441, 129951, 129321,
            128553, 127648, 126606, 125428, 124116,
            122671, 121095, 119389, 117555, 115595,
            113512, 111307, 108982, 106541, 103986,
            101320, 98545, 95665, 92682, 89600
        ),

        193 => (
            131003, 130794, 130447, 129962, 129339,
            128579, 127683, 126652, 125486, 124187,
            122757, 121197, 119508, 117692, 115752,
            113689, 111506, 109204, 106787, 104256,
            101615, 98867, 96013, 93058, 90005
        ),

        194 => (
            131003, 130797, 130454, 129974, 129357,
            128605, 127718, 126697, 125543, 124257,
            122842, 121297, 119625, 117827, 115906,
            113864, 111702, 109423, 107029, 104522,
            101907, 99184, 96357, 93429, 90403
        ),

        195 => (
            131004, 130800, 130460, 129985, 129375,
            128630, 127752, 126741, 125599, 124327,
            122925, 121396, 119740, 117961, 116058,
            114036, 111895, 109638, 107267, 104785,
            102193, 99496, 96696, 93795, 90797
        ),

        196 => (
            131005, 130803, 130466, 129996, 129392,
            128655, 127786, 126785, 125655, 124395,
            123007, 121493, 119854, 118092, 116208,
            114205, 112085, 109850, 107502, 105043,
            102476, 99804, 97030, 94155, 91185
        ),

        197 => (
            131005, 130805, 130472, 130007, 129409,
            128679, 127819, 126828, 125709, 124462,
            123088, 121589, 119966, 118221, 116356,
            114373, 112273, 110059, 107733, 105297,
            102755, 100108, 97359, 94511, 91567
        ),

        198 => (
            131006, 130808, 130478, 130018, 129426,
            128703, 127852, 126871, 125763, 124528,
            123167, 121683, 120076, 118348, 116501,
            114537, 112458, 110265, 107961, 105548,
            103030, 100407, 97683, 94861, 91944
        ),

        199 => (
            131007, 130811, 130484, 130028, 129442,
            128727, 127884, 126913, 125816, 124593,
            123246, 121776, 120185, 118474, 116645,
            114699, 112640, 110468, 108186, 105796,
            103300, 100702, 98003, 95207, 92315
        ),

        200 => (
            131007, 130813, 130490, 130038, 129458,
            128750, 127915, 126954, 125868, 124657,
            123323, 121868, 120292, 118597, 116786,
            114859, 112819, 110668, 108407, 106039,
            103567, 100993, 98319, 95547, 92682
        ),

        201 => (
            131008, 130816, 130496, 130049, 129474,
            128773, 127947, 126995, 125919, 124720,
            123399, 121958, 120397, 118719, 116925,
            115017, 112996, 110865, 108625, 106280,
            103830, 101279, 98630, 95883, 93043
        ),

        202 => (
            131009, 130818, 130502, 130059, 129490,
            128796, 127977, 127035, 125969, 124782,
            123474, 122047, 120501, 118839, 117062,
            115172, 113170, 111059, 108841, 106517,
            104090, 101562, 98936, 96215, 93400
        ),

        203 => (
            131009, 130821, 130507, 130069, 129506,
            128818, 128008, 127074, 126019, 124844,
            123548, 122135, 120604, 118958, 117198,
            115325, 113342, 111251, 109053, 106750,
            104346, 101841, 99239, 96541, 93751
        ),

        204 => (
            131010, 130823, 130513, 130079, 129521,
            128840, 128037, 127113, 126068, 124904,
            123621, 122221, 120705, 119074, 117331,
            115476, 113512, 111440, 109262, 106981,
            104598, 102116, 99537, 96863, 94098
        ),

        205 => (
            131010, 130826, 130518, 130088, 129536,
            128862, 128067, 127152, 126117, 124964,
            123693, 122306, 120804, 119189, 117462,
            115625, 113679, 111626, 109468, 107208,
            104846, 102387, 99831, 97181, 94440
        ),

        206 => (
            131011, 130828, 130524, 130098, 129551,
            128883, 128096, 127189, 126164, 125022,
            123764, 122390, 120903, 119303, 117592,
            115771, 113843, 111809, 109672, 107432,
            105092, 102654, 100121, 97495, 94778
        ),

        207 => (
            131012, 130831, 130529, 130107, 129565,
            128904, 128124, 127227, 126211, 125080,
            123834, 122473, 120999, 119414, 117719,
            115916, 114006, 111990, 109872, 107652,
            105334, 102918, 100407, 97804, 95110
        ),

        208 => (
            131012, 130833, 130534, 130116, 129580,
            128925, 128153, 127263, 126258, 125137,
            123902, 122554, 121095, 119525, 117845,
            116058, 114166, 112169, 110070, 107870,
            105572, 103178, 100689, 98109, 95439
        ),

        209 => (
            131013, 130835, 130539, 130125, 129594,
            128945, 128180, 127299, 126304, 125193,
            123970, 122635, 121189, 119633, 117969,
            116199, 114324, 112345, 110265, 108085,
            105807, 103434, 100968, 98410, 95763
        ),

        210 => (
            131013, 130837, 130544, 130134, 129608,
            128966, 128208, 127335, 126349, 125249,
            124037, 122714, 121281, 119740, 118092,
            116338, 114479, 112519, 110457, 108297,
            106039, 103687, 101242, 98707, 96083
        )

    );



    ------------------------------------------------------------------
    -- Exact coefficient lookup
    ------------------------------------------------------------------

    function get_coefficient (

        harmonic :
            integer;

        frame_count :
            integer

    ) return signed is


        variable safe_frame :
            integer range 190 to 210;


        variable safe_harmonic :
            integer range 1 to 25;


    begin


        if frame_count < 190 then

            safe_frame := 190;

        elsif frame_count > 210 then

            safe_frame := 210;

        else

            safe_frame := frame_count;

        end if;


        if harmonic < 1 then

            safe_harmonic := 1;

        elsif harmonic > 25 then

            safe_harmonic := 25;

        else

            safe_harmonic := harmonic;

        end if;


        return
            to_signed(
                COEFFICIENT_TABLE(
                    safe_frame
                )(
                    safe_harmonic
                ),
                18
            );


    end function;



    ------------------------------------------------------------------
    -- Processing FSM
    ------------------------------------------------------------------

    type processing_state_t is (

        IDLE,

        PREPARE_HARMONIC,

        REQUEST_SAMPLE,
        WAIT_SAMPLE,

        GOERTZEL_MUL,
        GOERTZEL_ADD,
        GOERTZEL_SUB,

        MAG_STAGE_1,
        MAG_STAGE_2,
        MAG_STAGE_3,
        MAG_STAGE_4,

        ACCUMULATE_MAGNITUDE,

        COMPLETE

    );


    signal state :
        processing_state_t :=
        IDLE;



begin


    ------------------------------------------------------------------
    -- External assignments
    ------------------------------------------------------------------

    read_index <=
        read_index_reg;


    voltage_fund_mag_sq <=
        voltage_fundamental_int;


    current_fund_mag_sq <=
        current_fundamental_int;


    voltage_harm_sum_sq <=
        voltage_harmonic_sum_int;


    current_harm_sum_sq <=
        current_harmonic_sum_int;


    harmonic_number <=
        to_unsigned(
            harmonic_index,
            harmonic_number'length
        );



    ------------------------------------------------------------------
    -- Harmonic processing FSM
    ------------------------------------------------------------------

    HARMONIC_PROC :
    process(clk_100mhz)


        variable voltage_scaled_product :
            state_value_t;


        variable current_scaled_product :
            state_value_t;


        variable voltage_cross_scaled :
            signed(79 downto 0);


        variable current_cross_scaled :
            signed(79 downto 0);


        variable voltage_magnitude_signed :
            signed(79 downto 0);


        variable current_magnitude_signed :
            signed(79 downto 0);


        variable count_value :
            integer;


    begin


        if rising_edge(clk_100mhz) then


            if reset = '1' then


                state <=
                    IDLE;


                read_index_reg <=
                    (others => '0');


                sample_index <=
                    0;


                frame_count_reg <=
                    200;


                harmonic_index <=
                    1;


                coefficient_reg <=
                    (others => '0');


                voltage_s1 <=
                    (others => '0');

                voltage_s2 <=
                    (others => '0');

                current_s1 <=
                    (others => '0');

                current_s2 <=
                    (others => '0');


                voltage_coeff_product_reg <=
                    (others => '0');

                current_coeff_product_reg <=
                    (others => '0');


                voltage_sample_reg <=
                    (others => '0');

                current_sample_reg <=
                    (others => '0');


                voltage_s2_delay_reg <=
                    (others => '0');

                current_s2_delay_reg <=
                    (others => '0');


                voltage_partial_sum_reg <=
                    (others => '0');

                current_partial_sum_reg <=
                    (others => '0');


                voltage_s2_stage3_reg <=
                    (others => '0');

                current_s2_stage3_reg <=
                    (others => '0');


                voltage_fundamental_int <=
                    (others => '0');

                current_fundamental_int <=
                    (others => '0');


                voltage_harmonic_sum_int <=
                    (others => '0');

                current_harmonic_sum_int <=
                    (others => '0');


                voltage_s1_square_reg <=
                    (others => '0');

                voltage_s2_square_reg <=
                    (others => '0');

                voltage_cross_reg <=
                    (others => '0');

                voltage_coeff_cross_reg <=
                    (others => '0');

                voltage_cross_scaled_reg <=
                    (others => '0');

                voltage_mag_sq_reg <=
                    (others => '0');


                current_s1_square_reg <=
                    (others => '0');

                current_s2_square_reg <=
                    (others => '0');

                current_cross_reg <=
                    (others => '0');

                current_coeff_cross_reg <=
                    (others => '0');

                current_cross_scaled_reg <=
                    (others => '0');

                current_mag_sq_reg <=
                    (others => '0');


                busy <=
                    '0';


                harmonic_valid <=
                    '0';



            else


                harmonic_valid <=
                    '0';



                case state is


                    --------------------------------------------------
                    -- IDLE
                    --------------------------------------------------

                    when IDLE =>


                        busy <=
                            '0';


                        if start = '1' then


                            count_value :=
                                to_integer(
                                    frame_sample_count
                                );


                            if count_value < 190 then

                                frame_count_reg <=
                                    190;

                            elsif count_value > FRAME_SAMPLES then

                                frame_count_reg <=
                                    FRAME_SAMPLES;

                            else

                                frame_count_reg <=
                                    count_value;

                            end if;


                            harmonic_index <=
                                1;


                            voltage_fundamental_int <=
                                (others => '0');

                            current_fundamental_int <=
                                (others => '0');


                            voltage_harmonic_sum_int <=
                                (others => '0');

                            current_harmonic_sum_int <=
                                (others => '0');


                            busy <=
                                '1';


                            state <=
                                PREPARE_HARMONIC;


                        end if;



                    --------------------------------------------------
                    -- PREPARE HARMONIC
                    --------------------------------------------------

                    when PREPARE_HARMONIC =>


                        busy <=
                            '1';


                        sample_index <=
                            0;


                        read_index_reg <=
                            (others => '0');


                        voltage_s1 <=
                            (others => '0');

                        voltage_s2 <=
                            (others => '0');


                        current_s1 <=
                            (others => '0');

                        current_s2 <=
                            (others => '0');


                        coefficient_reg <=
                            get_coefficient(
                                harmonic_index,
                                frame_count_reg
                            );


                        state <=
                            REQUEST_SAMPLE;



                    --------------------------------------------------
                    -- REQUEST SAMPLE
                    --------------------------------------------------

                    when REQUEST_SAMPLE =>


                        busy <=
                            '1';


                        read_index_reg <=
                            to_unsigned(
                                sample_index,
                                read_index_reg'length
                            );


                        state <=
                            WAIT_SAMPLE;



                    --------------------------------------------------
                    -- WAIT FOR BRAM
                    --------------------------------------------------

                    when WAIT_SAMPLE =>


                        busy <=
                            '1';


                        state <=
                            GOERTZEL_MUL;



                    --------------------------------------------------
                    -- GOERTZEL STAGE 1
                    --------------------------------------------------

                    when GOERTZEL_MUL =>


                        busy <=
                            '1';


                        voltage_coeff_product_reg <=
                            voltage_s1
                            *
                            coefficient_reg;


                        current_coeff_product_reg <=
                            current_s1
                            *
                            coefficient_reg;


                        voltage_sample_reg <=
                            voltage_sample_mV;


                        current_sample_reg <=
                            current_sample_uA;


                        voltage_s2_delay_reg <=
                            voltage_s2;


                        current_s2_delay_reg <=
                            current_s2;


                        state <=
                            GOERTZEL_ADD;



                    --------------------------------------------------
                    -- GOERTZEL STAGE 2
                    --------------------------------------------------

                    when GOERTZEL_ADD =>


                        busy <=
                            '1';


                        voltage_scaled_product :=
                            resize(
                                shift_right(
                                    voltage_coeff_product_reg,
                                    COEFF_SHIFT
                                ),
                                state_value_t'length
                            );


                        current_scaled_product :=
                            resize(
                                shift_right(
                                    current_coeff_product_reg,
                                    COEFF_SHIFT
                                ),
                                state_value_t'length
                            );


                        voltage_partial_sum_reg <=

                            resize(
                                voltage_sample_reg,
                                state_value_t'length
                            )

                            +

                            voltage_scaled_product;


                        current_partial_sum_reg <=

                            resize(
                                current_sample_reg,
                                state_value_t'length
                            )

                            +

                            current_scaled_product;


                        voltage_s2_stage3_reg <=
                            voltage_s2_delay_reg;


                        current_s2_stage3_reg <=
                            current_s2_delay_reg;


                        state <=
                            GOERTZEL_SUB;



                    --------------------------------------------------
                    -- GOERTZEL STAGE 3
                    --------------------------------------------------

                    when GOERTZEL_SUB =>


                        busy <=
                            '1';


                        voltage_s2 <=
                            voltage_s1;


                        voltage_s1 <=
                            voltage_partial_sum_reg
                            -
                            voltage_s2_stage3_reg;


                        current_s2 <=
                            current_s1;


                        current_s1 <=
                            current_partial_sum_reg
                            -
                            current_s2_stage3_reg;


                        if
                            sample_index =
                            frame_count_reg - 1
                        then


                            state <=
                                MAG_STAGE_1;


                        else


                            sample_index <=
                                sample_index + 1;


                            state <=
                                REQUEST_SAMPLE;


                        end if;



                    --------------------------------------------------
                    -- MAGNITUDE STAGE 1
                    --------------------------------------------------

                    when MAG_STAGE_1 =>


                        busy <=
                            '1';


                        voltage_s1_square_reg <=
                            voltage_s1
                            *
                            voltage_s1;


                        voltage_s2_square_reg <=
                            voltage_s2
                            *
                            voltage_s2;


                        voltage_cross_reg <=
                            voltage_s1
                            *
                            voltage_s2;


                        current_s1_square_reg <=
                            current_s1
                            *
                            current_s1;


                        current_s2_square_reg <=
                            current_s2
                            *
                            current_s2;


                        current_cross_reg <=
                            current_s1
                            *
                            current_s2;


                        state <=
                            MAG_STAGE_2;



                    --------------------------------------------------
                    -- MAGNITUDE STAGE 2
                    --------------------------------------------------

                    when MAG_STAGE_2 =>


                        busy <=
                            '1';


                        voltage_coeff_cross_reg <=
                            voltage_cross_reg
                            *
                            coefficient_reg;


                        current_coeff_cross_reg <=
                            current_cross_reg
                            *
                            coefficient_reg;


                        state <=
                            MAG_STAGE_3;



                    --------------------------------------------------
                    -- MAGNITUDE STAGE 3
                    --------------------------------------------------

                    when MAG_STAGE_3 =>


                        busy <=
                            '1';


                        voltage_cross_scaled :=
                            resize(
                                shift_right(
                                    voltage_coeff_cross_reg,
                                    COEFF_SHIFT
                                ),
                                80
                            );


                        current_cross_scaled :=
                            resize(
                                shift_right(
                                    current_coeff_cross_reg,
                                    COEFF_SHIFT
                                ),
                                80
                            );


                        voltage_cross_scaled_reg <=
                            voltage_cross_scaled;


                        current_cross_scaled_reg <=
                            current_cross_scaled;


                        state <=
                            MAG_STAGE_4;



                    --------------------------------------------------
                    -- MAGNITUDE STAGE 4
                    --------------------------------------------------

                    when MAG_STAGE_4 =>


                        busy <=
                            '1';


                        voltage_magnitude_signed :=

                            voltage_s1_square_reg

                            +

                            voltage_s2_square_reg

                            -

                            voltage_cross_scaled_reg;


                        current_magnitude_signed :=

                            current_s1_square_reg

                            +

                            current_s2_square_reg

                            -

                            current_cross_scaled_reg;


                        if voltage_magnitude_signed < 0 then

                            voltage_mag_sq_reg <=
                                (others => '0');

                        else

                            voltage_mag_sq_reg <=
                                unsigned(
                                    voltage_magnitude_signed
                                );

                        end if;


                        if current_magnitude_signed < 0 then

                            current_mag_sq_reg <=
                                (others => '0');

                        else

                            current_mag_sq_reg <=
                                unsigned(
                                    current_magnitude_signed
                                );

                        end if;


                        state <=
                            ACCUMULATE_MAGNITUDE;



                    --------------------------------------------------
                    -- ACCUMULATE
                    --------------------------------------------------

                    when ACCUMULATE_MAGNITUDE =>


                        busy <=
                            '1';


                        if harmonic_index = 1 then


                            voltage_fundamental_int <=
                                voltage_mag_sq_reg;


                            current_fundamental_int <=
                                current_mag_sq_reg;


                        else


                            voltage_harmonic_sum_int <=

                                voltage_harmonic_sum_int

                                +

                                resize(
                                    voltage_mag_sq_reg,
                                    voltage_harmonic_sum_int'length
                                );


                            current_harmonic_sum_int <=

                                current_harmonic_sum_int

                                +

                                resize(
                                    current_mag_sq_reg,
                                    current_harmonic_sum_int'length
                                );


                        end if;


                        if harmonic_index = 25 then


                            state <=
                                COMPLETE;


                        else


                            harmonic_index <=
                                harmonic_index + 1;


                            state <=
                                PREPARE_HARMONIC;


                        end if;



                    --------------------------------------------------
                    -- COMPLETE
                    --------------------------------------------------

                    when COMPLETE =>


                        busy <=
                            '0';


                        harmonic_valid <=
                            '1';


                        state <=
                            IDLE;



                    when others =>


                        busy <=
                            '0';


                        state <=
                            IDLE;


                end case;


            end if;


        end if;


    end process;


end architecture rtl;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity power_meter is

    generic (

        --------------------------------------------------------------
        -- Samples per measurement window
        --
        -- 10 kS/s / 50 Hz = 200
        --------------------------------------------------------------
        WINDOW_SAMPLES : positive := 200

    );

    port (

        --------------------------------------------------------------
        -- FPGA system
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;


        --------------------------------------------------------------
        -- Instantaneous synchronized physical samples
        --
        -- voltage_mV_in:
        --     millivolts
        --
        -- current_uA_in:
        --     microamps
        --------------------------------------------------------------
        voltage_mV_in : in signed(31 downto 0);
        current_uA_in : in signed(31 downto 0);


        --------------------------------------------------------------
        -- Valid pulse for instantaneous sample pair
        --------------------------------------------------------------
        sample_valid_in : in std_logic;


        --------------------------------------------------------------
        -- RMS values from dual_rms
        --------------------------------------------------------------
        voltage_rms_mV_in : in unsigned(31 downto 0);
        current_rms_uA_in : in unsigned(31 downto 0);


        --------------------------------------------------------------
        -- Active power
        --
        -- Units: milliwatts
        --------------------------------------------------------------
        active_power_mW : out signed(31 downto 0);


        --------------------------------------------------------------
        -- Apparent power
        --
        -- Units: milli-volt-amperes
        --------------------------------------------------------------
        apparent_power_mVA : out unsigned(31 downto 0);


        --------------------------------------------------------------
        -- Power factor ×1000
        --
        -- +1000 = +1.000
        --     0 =  0.000
        -- -1000 = -1.000
        --------------------------------------------------------------
        power_factor_milli : out signed(15 downto 0);


        --------------------------------------------------------------
        -- One-clock pulse when new P/S/PF results are ready
        --------------------------------------------------------------
        power_valid : out std_logic

    );

end entity power_meter;



architecture rtl of power_meter is


    ------------------------------------------------------------------
    -- Sample counter
    ------------------------------------------------------------------

    signal sample_count :
        integer range 0 to WINDOW_SAMPLES - 1 := 0;


    ------------------------------------------------------------------
    -- Accumulator for instantaneous power products
    --
    -- v[mV] × i[uA]
    --
    -- Units:
    --
    -- mV × uA = nW
    ------------------------------------------------------------------

    signal power_sum_nW :
        signed(63 downto 0) := (others => '0');


begin


    ------------------------------------------------------------------
    -- Power measurement process
    ------------------------------------------------------------------

    power_process : process(clk_100mhz)

        --------------------------------------------------------------
        -- Instantaneous power product
        --------------------------------------------------------------

        variable instant_power_nW :
            signed(63 downto 0);


        --------------------------------------------------------------
        -- Final window sum including current sample
        --------------------------------------------------------------

        variable total_power_nW :
            signed(63 downto 0);


        --------------------------------------------------------------
        -- Mean active power in nW
        --------------------------------------------------------------

        variable mean_power_nW :
            signed(63 downto 0);


        --------------------------------------------------------------
        -- Active power converted to mW
        --
        -- 1 mW = 1,000,000 nW
        --------------------------------------------------------------

        variable active_mW_64 :
            signed(63 downto 0);


        --------------------------------------------------------------
        -- Apparent power:
        --
        -- Vrms[mV] × Irms[uA] = nVA
        --------------------------------------------------------------

        variable apparent_nVA :
            unsigned(63 downto 0);


        variable apparent_mVA_64 :
            unsigned(63 downto 0);


        --------------------------------------------------------------
        -- PF arithmetic
        --------------------------------------------------------------

        variable abs_active_mW :
            unsigned(63 downto 0);

        variable pf_numerator :
            unsigned(63 downto 0);

        variable pf_magnitude :
            unsigned(63 downto 0);

        variable pf_signed :
            signed(15 downto 0);


    begin

        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then

                sample_count <= 0;

                power_sum_nW <= (others => '0');

                active_power_mW <= (others => '0');
                apparent_power_mVA <= (others => '0');
                power_factor_milli <= (others => '0');

                power_valid <= '0';


            else


                ------------------------------------------------------
                -- Default
                ------------------------------------------------------

                power_valid <= '0';


                ------------------------------------------------------
                -- Process only new synchronized samples
                ------------------------------------------------------

                if sample_valid_in = '1' then


                    --------------------------------------------------
                    -- Instantaneous real power:
                    --
                    -- v[mV] × i[uA]
                    --
                    -- signed 32 × signed 32 = signed 64
                    --------------------------------------------------

                    instant_power_nW :=
                        voltage_mV_in *
                        current_uA_in;


                    --------------------------------------------------
                    -- Last sample of window
                    --------------------------------------------------

                    if sample_count = WINDOW_SAMPLES - 1 then


                        ------------------------------------------------
                        -- Include final sample
                        ------------------------------------------------

                        total_power_nW :=
                            power_sum_nW +
                            instant_power_nW;


                        ------------------------------------------------
                        -- Average instantaneous power
                        ------------------------------------------------

                        mean_power_nW :=
                            total_power_nW /
                            WINDOW_SAMPLES;


                        ------------------------------------------------
                        -- Convert nW → mW
                        --
                        -- divide by 1,000,000
                        ------------------------------------------------

                        active_mW_64 :=
                            mean_power_nW /
                            1_000_000;


                        ------------------------------------------------
                        -- Publish active power
                        ------------------------------------------------

                        active_power_mW <=
                            resize(
                                active_mW_64,
                                active_power_mW'length
                            );


                        ------------------------------------------------
                        -- Apparent power
                        --
                        -- mV × uA = nVA
                        ------------------------------------------------

                        apparent_nVA :=
                            voltage_rms_mV_in *
                            current_rms_uA_in;


                        ------------------------------------------------
                        -- nVA → mVA
                        ------------------------------------------------

                        apparent_mVA_64 :=
                            apparent_nVA /
                            1_000_000;


                        apparent_power_mVA <=
                            resize(
                                apparent_mVA_64,
                                apparent_power_mVA'length
                            );


                        ------------------------------------------------
                        -- Power factor
                        --
                        -- PF_milli =
                        --
                        -- |P_mW| × 1000
                        -- ----------------
                        -- S_mVA
                        ------------------------------------------------

                        if apparent_mVA_64 /= 0 then


                            ------------------------------------------------
                            -- Absolute active power
                            ------------------------------------------------

                            if active_mW_64 < 0 then

                                abs_active_mW :=
                                    unsigned(
                                        -active_mW_64
                                    );

                            else

                                abs_active_mW :=
                                    unsigned(
                                        active_mW_64
                                    );

                            end if;


                            ------------------------------------------------
                            -- ×1000 without oversized multiplication
                            --
                            -- 1000 = 1024 - 16 - 8
                            ------------------------------------------------

                            pf_numerator :=
                                shift_left(abs_active_mW, 10)
                                -
                                shift_left(abs_active_mW, 4)
                                -
                                shift_left(abs_active_mW, 3);


                            pf_magnitude :=
                                pf_numerator /
                                apparent_mVA_64;


                            ------------------------------------------------
                            -- Clamp to 1000 in case of tiny rounding
                            -- overshoot
                            ------------------------------------------------

                            if pf_magnitude > 1000 then

                                pf_magnitude :=
                                    to_unsigned(1000, 64);

                            end if;


                            ------------------------------------------------
                            -- Restore active-power sign
                            ------------------------------------------------

                            if active_mW_64 < 0 then

                                pf_signed :=
                                    -to_signed(
                                        to_integer(pf_magnitude),
                                        16
                                    );

                            else

                                pf_signed :=
                                    to_signed(
                                        to_integer(pf_magnitude),
                                        16
                                    );

                            end if;


                            power_factor_milli <= pf_signed;


                        else

                            power_factor_milli <=
                                (others => '0');

                        end if;


                        ------------------------------------------------
                        -- New result ready
                        ------------------------------------------------

                        power_valid <= '1';


                        ------------------------------------------------
                        -- Reset window
                        ------------------------------------------------

                        sample_count <= 0;

                        power_sum_nW <= (others => '0');


                    --------------------------------------------------
                    -- Continue accumulating
                    --------------------------------------------------

                    else

                        power_sum_nW <=
                            power_sum_nW +
                            instant_power_nW;

                        sample_count <=
                            sample_count + 1;

                    end if;

                end if;

            end if;

        end if;

    end process;


end architecture rtl;
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity thd_13_meter is

    port (

        --------------------------------------------------------------
        -- FPGA system
        --------------------------------------------------------------
        clk_100mhz : in std_logic;
        reset      : in std_logic;


        --------------------------------------------------------------
        -- Input from harmonic_13_extractor
        --------------------------------------------------------------
        voltage_fund_mag_sq :
            in unsigned(79 downto 0);

        voltage_3rd_mag_sq :
            in unsigned(79 downto 0);

        current_fund_mag_sq :
            in unsigned(79 downto 0);

        current_3rd_mag_sq :
            in unsigned(79 downto 0);


        --------------------------------------------------------------
        -- Pulses when new harmonic values are ready
        --------------------------------------------------------------
        harmonic_valid_in :
            in std_logic;


        --------------------------------------------------------------
        -- THD outputs
        --
        -- percent x100
        --
        -- 1000 = 10.00 %
        -- 2000 = 20.00 %
        --------------------------------------------------------------
        voltage_thd_x100 :
            out unsigned(15 downto 0);

        current_thd_x100 :
            out unsigned(15 downto 0);


        --------------------------------------------------------------
        -- One-clock result-valid pulse
        --------------------------------------------------------------
        thd_valid :
            out std_logic

    );

end entity thd_13_meter;



architecture rtl of thd_13_meter is


    ------------------------------------------------------------------
    -- We calculate:
    --
    -- THD_x100 =
    --
    -- sqrt(
    --      harmonic_mag_sq * 100,000,000
    --      --------------------------------
    --              fundamental_mag_sq
    -- )
    --
    --
    -- Why 100,000,000?
    --
    -- sqrt(100,000,000) = 10,000
    --
    -- and:
    --
    -- harmonic/fundamental × 10,000
    --
    -- gives:
    --
    -- ratio × 100% × 100
    --
    -- Example:
    --
    -- V3/V1 = 0.10
    --
    -- 0.10 × 10,000 = 1000
    --
    -- = 10.00 %
    ------------------------------------------------------------------



    ------------------------------------------------------------------
    -- Fixed-width multiply-by-100,000,000 function
    --
    -- 100,000,000 binary set bits:
    --
    -- 26,24,23,22,21,20,18,16,15,14,13,8
    --
    -- Using shifts avoids a wide VHDL multiplication result.
    ------------------------------------------------------------------

    function multiply_by_100m (
        value_in : unsigned(79 downto 0)
    ) return unsigned is

        variable x :
            unsigned(127 downto 0);

        variable result_value :
            unsigned(127 downto 0);

    begin

        x :=
            resize(
                value_in,
                128
            );


        result_value :=
              shift_left(x, 26)
            + shift_left(x, 24)
            + shift_left(x, 23)
            + shift_left(x, 22)
            + shift_left(x, 21)
            + shift_left(x, 20)
            + shift_left(x, 18)
            + shift_left(x, 16)
            + shift_left(x, 15)
            + shift_left(x, 14)
            + shift_left(x, 13)
            + shift_left(x, 8);


        return result_value;

    end function;



    ------------------------------------------------------------------
    -- Integer square-root
    --
    -- Input is 64 bits.
    -- Output is floor(sqrt(input)).
    ------------------------------------------------------------------

    function integer_sqrt_64 (
        value : unsigned(63 downto 0)
    ) return unsigned is

        variable root :
            unsigned(31 downto 0) :=
            (others => '0');

        variable candidate :
            unsigned(31 downto 0);

        variable square :
            unsigned(63 downto 0);

    begin


        for bit_index in 31 downto 0 loop

            candidate := root;

            candidate(bit_index) := '1';


            square :=
                candidate *
                candidate;


            if square <= value then

                root := candidate;

            end if;

        end loop;


        return root;

    end function;



begin


    ------------------------------------------------------------------
    -- THD calculation
    ------------------------------------------------------------------

    thd_process : process(clk_100mhz)


        variable voltage_numerator :
            unsigned(127 downto 0);

        variable current_numerator :
            unsigned(127 downto 0);


        variable voltage_ratio_sq :
            unsigned(127 downto 0);

        variable current_ratio_sq :
            unsigned(127 downto 0);


        variable voltage_ratio_64 :
            unsigned(63 downto 0);

        variable current_ratio_64 :
            unsigned(63 downto 0);


        variable voltage_root :
            unsigned(31 downto 0);

        variable current_root :
            unsigned(31 downto 0);


    begin

        if rising_edge(clk_100mhz) then


            ----------------------------------------------------------
            -- RESET
            ----------------------------------------------------------

            if reset = '1' then

                voltage_thd_x100 <=
                    (others => '0');

                current_thd_x100 <=
                    (others => '0');

                thd_valid <= '0';


            else


                ------------------------------------------------------
                -- Default
                ------------------------------------------------------

                thd_valid <= '0';


                ------------------------------------------------------
                -- Process new harmonic set
                ------------------------------------------------------

                if harmonic_valid_in = '1' then


                    --------------------------------------------------
                    -- VOLTAGE THD
                    --------------------------------------------------

                    if voltage_fund_mag_sq /= 0 then


                        voltage_numerator :=
                            multiply_by_100m(
                                voltage_3rd_mag_sq
                            );


                        voltage_ratio_sq :=
                            voltage_numerator
                            /
                            resize(
                                voltage_fund_mag_sq,
                                128
                            );


                        ------------------------------------------------
                        -- Ratio should be modest for real THD.
                        --
                        -- Reduce to 64 bits for square-root stage.
                        ------------------------------------------------

                        voltage_ratio_64 :=
                            resize(
                                voltage_ratio_sq,
                                64
                            );


                        voltage_root :=
                            integer_sqrt_64(
                                voltage_ratio_64
                            );


                        ------------------------------------------------
                        -- Saturate to 16-bit output if necessary
                        ------------------------------------------------

                        if voltage_root >
                           to_unsigned(65535, 32)
                        then

                            voltage_thd_x100 <=
                                to_unsigned(
                                    65535,
                                    16
                                );

                        else

                            voltage_thd_x100 <=
                                resize(
                                    voltage_root,
                                    16
                                );

                        end if;


                    else


                        voltage_thd_x100 <=
                            (others => '0');


                    end if;



                    --------------------------------------------------
                    -- CURRENT THD
                    --------------------------------------------------

                    if current_fund_mag_sq /= 0 then


                        current_numerator :=
                            multiply_by_100m(
                                current_3rd_mag_sq
                            );


                        current_ratio_sq :=
                            current_numerator
                            /
                            resize(
                                current_fund_mag_sq,
                                128
                            );


                        current_ratio_64 :=
                            resize(
                                current_ratio_sq,
                                64
                            );


                        current_root :=
                            integer_sqrt_64(
                                current_ratio_64
                            );


                        if current_root >
                           to_unsigned(65535, 32)
                        then

                            current_thd_x100 <=
                                to_unsigned(
                                    65535,
                                    16
                                );

                        else

                            current_thd_x100 <=
                                resize(
                                    current_root,
                                    16
                                );

                        end if;


                    else


                        current_thd_x100 <=
                            (others => '0');


                    end if;



                    --------------------------------------------------
                    -- Result available
                    --------------------------------------------------

                    thd_valid <= '1';


                end if;

            end if;

        end if;

    end process;


end architecture rtl;
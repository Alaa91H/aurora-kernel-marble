# arch/arm64/boot/dts/qcom/Makefile
#
# Makefile additions for the marble board DTS.
# This file is appended to the ACK qcom Makefile during setup.
# Only the board-level DTS is shipped; SoC-level dtsi come from the ACK tree.

# Marble board (POCO F5 / Redmi Note 12 Turbo)
# Platform: SM8450 (waipio/taro), SM7475 (diwali) die
# Uses CONFIG_ARCH_WAIPIO (not a separate SM7475 arch)
dtb-$(CONFIG_ARCH_WAIPIO) += \
    marble-board.dtb

# overlays
dtbo-$(CONFIG_ARCH_WAIPIO) += \
    marble-board.dtbo

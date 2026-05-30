################################################################################
#
# m4 — override version to 1.4.18 which builds cleanly with gcc 12+
#
################################################################################

M4_VERSION = 1.4.18
M4_SOURCE = m4-$(M4_VERSION).tar.xz
M4_SITE = $(BR2_GNU_MIRROR)/m4
M4_LICENSE = GPL-3.0+
M4_LICENSE_FILES = COPYING
M4_CPE_ID_VENDOR = gnu

HOST_M4_CONF_ENV = gl_cv_func_gettimeofday_clobber=no
HOST_M4_CONF_OPTS = --disable-assert

$(eval $(autotools-package))
$(eval $(host-autotools-package))

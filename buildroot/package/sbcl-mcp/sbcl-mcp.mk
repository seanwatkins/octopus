################################################################################
#
# sbcl-mcp
#
# Installs the pre-compiled SBCL MCP server core into the target image.
# Built by scripts/build-sbcl-core.sh — must be run before make-image.sh.
#
################################################################################

SBCL_MCP_VERSION     = 1.0
SBCL_MCP_SITE        = $(BR2_EXTERNAL_OCTOPUS_PATH)/../prebuilt
SBCL_MCP_SITE_METHOD = local

define SBCL_MCP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/mcp-server \
		$(TARGET_DIR)/usr/local/bin/mcp-server
	$(INSTALL) -D -m 0644 $(@D)/mcp-server.env.example \
		$(TARGET_DIR)/etc/octopus.env.example
endef

$(eval $(generic-package))

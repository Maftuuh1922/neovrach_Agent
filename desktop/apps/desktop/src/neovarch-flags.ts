/**
 * Neovarch Agent build flags.
 *
 * Neovarch Agent is a fork of Hermes Desktop. The upstream app offers to share
 * usage metrics with Nous Research through the Hermes backend; Neovarch ships
 * with that collection disabled: no first-run offer, no consent strip, and the
 * desktop never records usage events. The Settings page can still show and
 * change the backend's own opt-ins, which stay off unless the user enables them.
 */
export const NEOVARCH_DESKTOP_METRICS_ENABLED = false

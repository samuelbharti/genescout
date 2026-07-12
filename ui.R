navbarPage(
  title = "CANDID",
  # Apply branding from _brand.yml (colors, fonts). brand = TRUE requires the
  # file to exist; switch to bslib::bs_theme() to make it optional.
  theme = bslib::bs_theme(brand = TRUE),
  tabPanel("Review", review_page),
  tabPanel("Connectors", connectors_page),
  tabPanel("About", about_page)
)

navbarPage(
  title = "GeneScout",
  # Apply branding from _brand.yml (colors, fonts). brand = TRUE requires the
  # file to exist; switch to bslib::bs_theme() to make it optional.
  theme = bslib::bs_theme(brand = TRUE),
  tabPanel("Review", review_page),
  tabPanel("Chat", chat_page),
  tabPanel("Reading results", guide_page),
  tabPanel("Connectors", connectors_page),
  tabPanel("AI Agents", agents_page),
  tabPanel("About", about_page)
)

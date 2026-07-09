# About page: what CANDID is, and the research-use-only disclaimer.
about_page <- fluidPage(
  titlePanel("About CANDID"),
  hr(),
  fluidRow(
    column(
      width = 8,
      p(
        "CANDID (Candidate Annotation aNd Disease-informed Interpretation of",
        "eviDence) turns a candidate list - variants, genes, or perturbation",
        "hits - plus a biological context into a plausibility-ranked, cited",
        "research review: what each candidate is, what evidence supports it,",
        "what is uncertain, and what to test next."
      ),
      div(
        class = "alert alert-warning",
        role = "alert",
        tags$strong("Research use only. "),
        "CANDID is a hypothesis-prioritization aid for researchers. It is not a",
        "clinical decision-support tool and does not provide diagnosis,",
        "treatment guidance, or ACMG/AMP variant classification."
      )
    ),
    column(
      width = 4,
      tags$h4("How it works"),
      tags$ol(
        tags$li("Parse the candidate list and load the disease context."),
        tags$li(
          "Fan out to variant-effect, pathway/disease, and literature agents."
        ),
        tags$li("Gate every claim on a source, then score and apply caveats."),
        tags$li("Assemble an auditable, cited report.")
      )
    )
  )
)

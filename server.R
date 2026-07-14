# CANDID Shiny server. The Review tab owns the pipeline; the Chat tab is a grounded
# assistant. Two pieces of state are shared across tabs at the session level: the
# BYOK credential the user pastes on the Review tab (`creds`) and the current ranked
# run (`shared_result`), which grounds the chat.
function(input, output, session) {
  creds <- reactiveVal(NULL)
  shared_result <- reactiveVal(NULL)
  review_server("review", creds = creds, shared_result = shared_result)
  chat_server("chat", creds = creds, result_r = shared_result)
}

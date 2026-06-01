vim9script

# vim-ai OpenRouter configuration.

def g:OpenRouterVimAIToken(): string
  return $OPENROUTER_VIM_AI_API_KEY
enddef

g:vim_ai_complete = {
  provider: 'openai',
  options: {
    endpoint_url: 'https://openrouter.ai/api/v1/chat/completions',
    auth_type: 'bearer',
    token_load_fn: 'g:OpenRouterVimAIToken()',
    model: 'poolside/laguna-xs.2:free',
    temperature: 0.2,
  },
}

g:vim_ai_chat = {
  provider: 'openai',
  options: {
    endpoint_url: 'poolside/laguna-m.1:free',
    auth_type: 'bearer',
    token_load_fn: 'g:OpenRouterVimAIToken()',
    model: 'poolside/laguna-xs.2:free',
    temperature: 0.2,
  },
}

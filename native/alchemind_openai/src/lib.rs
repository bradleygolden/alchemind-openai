use rustler::{Env, Error, NifResult, NifStruct, ResourceArc, Term};
use std::sync::{Arc, Mutex};
use serde::{Deserialize, Serialize};

use async_openai::{
    config::OpenAIConfig,
    types::{ChatCompletionRequestSystemMessageArgs, ChatCompletionRequestUserMessageArgs, CreateChatCompletionRequestArgs, 
            CreateTranscriptionRequestArgs, CreateSpeechRequestArgs, SpeechModel, Voice, AudioInput, AudioResponseFormat},
    Client as OpenAIClient,
};
use std::collections::HashMap;
// Used for the StreamExt trait which provides the next() method for async streams
use futures_util::StreamExt;

// Define the resource struct that will be accessible from Elixir
pub struct OpenAIClientResource {
    client: Arc<Mutex<OpenAIClient<OpenAIConfig>>>,
}

// Register the resource type with Rustler at the top level - Reverted, moved back to on_load
// rustler::resource!(OpenAIClientResource, env);

#[derive(Debug, NifStruct, Serialize, Deserialize)]
#[module = "Alchemind.OpenAI.Message"]
struct Message {
    role: String,
    content: String,
}

#[rustler::nif]
fn create_client(api_key: &str, base_url: &str) -> NifResult<ResourceArc<OpenAIClientResource>> {
    let config = OpenAIConfig::new()
        .with_api_key(api_key)
        .with_api_base(base_url);
    
    let client = OpenAIClient::with_config(config);
    
    Ok(ResourceArc::new(OpenAIClientResource {
        client: Arc::new(Mutex::new(client)),
    }))
}

#[rustler::nif]
fn complete_chat(client_resource: ResourceArc<OpenAIClientResource>, messages: Vec<Message>, model: &str) -> NifResult<String> {
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return Err(Error::Term(Box::new("Failed to create Tokio runtime"))),
    };
    
    // Access the client field correctly through the ResourceArc
    let client = client_resource.client.lock().unwrap();
    
    // Convert messages to OpenAI format
    let mut chat_messages = Vec::new();
    
    for msg in messages {
        match msg.role.as_str() {
            "system" => {
                let message = ChatCompletionRequestSystemMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build system message: {}", e))))?;
                chat_messages.push(message.into());
            },
            "assistant" => {
                let message = async_openai::types::ChatCompletionRequestAssistantMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build assistant message: {}", e))))?;
                chat_messages.push(message.into());
            },
            _ => { // default to user message
                let message = ChatCompletionRequestUserMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build user message: {}", e))))?;
                chat_messages.push(message.into());
            }
        }
    }
    
    // Create the completion request
    let request = CreateChatCompletionRequestArgs::default()
        .model(model)
        .messages(chat_messages)
        .build()
        .map_err(|e| Error::Term(Box::new(format!("Failed to build request: {}", e))))?;
    
    // Send the request and get the response
    let response = runtime.block_on(async {
        client.chat().create(request).await
    });
    
    match response {
        Ok(completion) => {
            // Get the assistant's message
            if let Some(choice) = completion.choices.first() {
                if let Some(content) = &choice.message.content {
                    Ok(content.clone())
                } else {
                    Ok(String::new())
                }
            } else {
                Err(Error::Term(Box::new("No completion choices returned")))
            }
        },
        Err(e) => Err(Error::Term(Box::new(format!("API request failed: {}", e)))),
    }
}

// Instead of trying to implement the streaming in Rust, which is complex due to thread safety,
// let's use a more pragmatic approach: we'll create a function that processes a small chunk
// of the streaming response and call this function multiple times from Elixir to simulate streaming.

#[rustler::nif]
fn process_completion_chunk(env: Env, client_resource: ResourceArc<OpenAIClientResource>, messages: Vec<Message>, model: &str, stream_pid: rustler::LocalPid, ref_term: Term) -> NifResult<rustler::Atom> {
    // We'll use a simpler approach - just initiating the request and letting Elixir handle the streaming
    let runtime = tokio::runtime::Runtime::new().map_err(|e| Error::Term(Box::new(format!("Failed to create Tokio runtime: {}", e))))?;
    
    // Access the client field correctly through the ResourceArc
    let client = match client_resource.client.lock() {
        Ok(client) => client.clone(),
        Err(e) => return Err(Error::Term(Box::new(format!("Failed to lock client: {}", e)))),
    };
    
    // Convert messages to OpenAI format
    let mut chat_messages = Vec::new();
    
    for msg in messages {
        match msg.role.as_str() {
            "system" => {
                let message = ChatCompletionRequestSystemMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build system message: {}", e))))?;
                chat_messages.push(message.into());
            },
            "assistant" => {
                let message = async_openai::types::ChatCompletionRequestAssistantMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build assistant message: {}", e))))?;
                chat_messages.push(message.into());
            },
            _ => { // default to user message
                let message = ChatCompletionRequestUserMessageArgs::default()
                    .content(msg.content)
                    .build()
                    .map_err(|e| Error::Term(Box::new(format!("Failed to build user message: {}", e))))?;
                chat_messages.push(message.into());
            }
        }
    }
    
    // Create the completion request with streaming enabled
    let request = CreateChatCompletionRequestArgs::default()
        .model(model)
        .messages(chat_messages)
        .stream(true)
        .build()
        .map_err(|e| Error::Term(Box::new(format!("Failed to build request: {}", e))))?;
    
    // Process the request in the runtime but in a blocking way
    let result = runtime.block_on(async {
        // Create the stream
        let mut stream = match client.chat().create_stream(request).await {
            Ok(s) => s,
            Err(e) => return Err(format!("Failed to create stream: {}", e)),
        };
        
        // Process up to 10 chunks to keep it responsive
        let mut chunks = Vec::new();
        let mut is_done = false;
        
        for _ in 0..10 {
            match stream.next().await {
                Some(Ok(response)) => {
                    for choice in response.choices {
                        if let Some(content) = &choice.delta.content {
                            chunks.push(content.clone());
                        }
                        if choice.finish_reason.is_some() {
                            is_done = true;
                        }
                    }
                },
                Some(Err(e)) => return Err(format!("Stream error: {}", e)),
                None => {
                    is_done = true;
                    break;
                }
            }
        }
        
        Ok((chunks, is_done))
    });
    
    match result {
        Ok((chunks, is_done)) => {
            // Send the chunks to the Elixir process
            for chunk in chunks {
                let _ = env.send(&stream_pid, (atoms::stream_chunk(), chunk, ref_term.clone()));
            }
            
            // If we're done, send the done message
            if is_done {
                let _ = env.send(&stream_pid, (atoms::stream_done(), ref_term.clone()));
            }
            
            Ok(atoms::ok())
        },
        Err(error_msg) => {
            // Send the error to the Elixir process
            let _ = env.send(&stream_pid, (atoms::stream_error(), error_msg, ref_term.clone()));
            Ok(atoms::ok())
        }
    }
}

#[rustler::nif]
fn transcribe_audio(client_resource: ResourceArc<OpenAIClientResource>, audio_binary: Vec<u8>, opts: HashMap<String, Term>) -> NifResult<String> {
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return Err(Error::Term(Box::new("Failed to create Tokio runtime"))),
    };
    
    // Access the client field correctly through the ResourceArc
    let client = match client_resource.client.lock() {
        Ok(client) => client,
        Err(e) => return Err(Error::Term(Box::new(format!("Failed to lock client: {}", e))))
    };
    
    let debug_info = format!("Audio binary length: {}, Opts: {:?}", audio_binary.len(), opts.keys().collect::<Vec<_>>());
    
    // Audio binary should have a minimum length
    if audio_binary.len() < 10 {
        return Err(Error::Term(Box::new(format!("Audio binary too small. {}", debug_info))));
    }
    
    // Extract options with defaults
    let model = if let Some(term) = opts.get("model") {
        if term.is_atom() {
            "whisper-1".to_string()
        } else {
            match term.decode::<String>() {
                Ok(s) => s,
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode model: {:?}", e))))
            }
        }
    } else {
        "whisper-1".to_string()
    };
    
    let language = if let Some(term) = opts.get("language") {
        if term.is_atom() {
            None
        } else {
            match term.decode::<String>() {
                Ok(s) => Some(s),
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode language: {:?}", e))))
            }
        }
    } else {
        None
    };
    
    let prompt = if let Some(term) = opts.get("prompt") {
        if term.is_atom() {
            None
        } else {
            match term.decode::<String>() {
                Ok(s) => Some(s),
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode prompt: {:?}", e))))
            }
        }
    } else {
        None
    };
    
    let response_format = if let Some(term) = opts.get("response_format") {
        if term.is_atom() {
            "text".to_string()
        } else {
            match term.decode::<String>() {
                Ok(s) => s,
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode response_format: {:?}", e))))
            }
        }
    } else {
        "text".to_string()
    };
    
    let temperature = if let Some(term) = opts.get("temperature") {
        if term.is_atom() {
            None
        } else {
            match term.decode::<f32>() {
                Ok(t) => Some(t),
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode temperature: {:?}", e))))
            }
        }
    } else {
        None
    };
    
    // Create the audio input from binary data
    let file_name = format!("audio-{}.webm", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs());
    let audio_input = AudioInput::from_vec_u8(file_name, audio_binary);
    
    // Create the transcription request using the correct builder pattern with a binding
    let mut args = CreateTranscriptionRequestArgs::default();
    let mut request = args
        .file(audio_input)
        .model(&model);
    
    if let Some(lang) = language {
        request = request.language(&lang);
    }
    
    if let Some(p) = prompt {
        request = request.prompt(&p);
    }
    
    // Set response format using the correct enum
    let response_format_enum = match response_format.as_str() {
        "json" => AudioResponseFormat::Json,
        "srt" => AudioResponseFormat::Srt,
        "verbose_json" => AudioResponseFormat::VerboseJson,
        "vtt" => AudioResponseFormat::Vtt,
        _ => AudioResponseFormat::Text,
    };
    
    request = request.response_format(response_format_enum);
    
    if let Some(temp) = temperature {
        request = request.temperature(temp);
    }
    
    // Build the final request
    let request = match request.build() {
        Ok(req) => req,
        Err(e) => return Err(Error::Term(Box::new(format!("Failed to build request: {:?}", e))))
    };
    
    // Send the request and get the response
    let response = runtime.block_on(async {
        client.audio().transcribe(request).await
    });
    
    match response {
        Ok(transcription) => {
            Ok(transcription.text)
        },
        Err(e) => Err(Error::Term(Box::new(format!("API transcription request failed: {}", e)))),
    }
}

#[rustler::nif]
fn text_to_speech(client_resource: ResourceArc<OpenAIClientResource>, input: String, opts: HashMap<String, Term>) -> NifResult<Vec<u8>> {
    let runtime = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return Err(Error::Term(Box::new("Failed to create Tokio runtime"))),
    };
    
    // Access the client field correctly through the ResourceArc
    let client = match client_resource.client.lock() {
        Ok(client) => client,
        Err(e) => return Err(Error::Term(Box::new(format!("Failed to lock client: {}", e))))
    };
    
    let debug_info = format!("Input text length: {}, Opts: {:?}", input.len(), opts.keys().collect::<Vec<_>>());
    
    // Extract options with defaults
    let model_str = if let Some(term) = opts.get("model") {
        if term.is_atom() {
            "tts-1".to_string()
        } else {
            match term.decode::<String>() {
                Ok(s) => s,
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode model: {:?}. {}", e, debug_info))))
            }
        }
    } else {
        "tts-1".to_string()
    };
    
    let model = match model_str.as_str() {
        "tts-1-hd" => SpeechModel::Tts1Hd,
        _ => SpeechModel::Tts1,  // Default to tts-1
    };
    
    let voice_str = if let Some(term) = opts.get("voice") {
        if term.is_atom() {
            "alloy".to_string()
        } else {
            match term.decode::<String>() {
                Ok(s) => s,
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode voice: {:?}. {}", e, debug_info))))
            }
        }
    } else {
        "alloy".to_string()
    };
    
    let voice = match voice_str.as_str() {
        "echo" => Voice::Echo,
        "fable" => Voice::Fable,
        "onyx" => Voice::Onyx,
        "nova" => Voice::Nova,
        "shimmer" => Voice::Shimmer,
        _ => Voice::Alloy,  // Default to alloy
    };
    
    let format_str = if let Some(term) = opts.get("response_format") {
        if term.is_atom() {
            "mp3".to_string()
        } else {
            match term.decode::<String>() {
                Ok(s) => s,
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode response_format: {:?}. {}", e, debug_info))))
            }
        }
    } else {
        "mp3".to_string()
    };
    
    let response_format = match format_str.as_str() {
        "opus" => async_openai::types::SpeechResponseFormat::Opus,
        "aac" => async_openai::types::SpeechResponseFormat::Aac,
        "flac" => async_openai::types::SpeechResponseFormat::Flac,
        _ => async_openai::types::SpeechResponseFormat::Mp3,
    };
    
    let speed = if let Some(term) = opts.get("speed") {
        if term.is_atom() {
            None
        } else {
            match term.decode::<f32>() {
                Ok(s) => Some(s),
                Err(e) => return Err(Error::Term(Box::new(format!("Failed to decode speed: {:?}. {}", e, debug_info))))
            }
        }
    } else {
        None
    };
    
    // Create the speech request with a binding to avoid temporary value issue
    let mut args = CreateSpeechRequestArgs::default();
    let mut request = args
        .input(&input)
        .model(model)
        .voice(voice)
        .response_format(response_format);
    
    if let Some(spd) = speed {
        request = request.speed(spd);
    }
    
    let request = match request.build() {
        Ok(req) => req,
        Err(e) => return Err(Error::Term(Box::new(format!("Failed to build speech request: {:?}. {}", e, debug_info))))
    };
    
    // Send the request and get the response
    let response = runtime.block_on(async {
        client.audio().speech(request).await
    });
    
    match response {
        Ok(bytes) => {
            match bytes.bytes.to_vec() {
                bytes => Ok(bytes),
                //Err(e) => Err(Error::Term(Box::new(format!("Failed to convert bytes: {:?}. {}", e, debug_info))))
            }
        },
        Err(e) => Err(Error::Term(Box::new(format!("API speech request failed: {}. {}", e, debug_info)))),
    }
}

// Load function to register the resource type
fn on_load(env: Env, _info: Term) -> bool {
    // Register the resource type with Rustler
    rustler::resource!(OpenAIClientResource, env);
    true
}

// Define our atoms
mod atoms {
    rustler::atoms! {
        ok,
        error,
        stream_chunk,
        stream_error,
        stream_done
    }
}

rustler::init!(
    "Elixir.Alchemind.OpenAI",
    // [ // Deprecated argument, remove the list of functions - Kept from previous edit
    //     create_client,
    //     complete_chat,
    //     process_completion_chunk,
    //     transcribe_audio,
    //     text_to_speech
    // ],
    load = on_load
);

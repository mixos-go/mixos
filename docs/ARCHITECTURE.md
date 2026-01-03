# MixOS-GO Technical Architecture

> Detailed technical specification for the MixOS-GO Agent System

## Table of Contents

1. [System Components](#system-components)
2. [Agent System Design](#agent-system-design)
3. [LLM Backend Architecture](#llm-backend-architecture)
4. [Tool System](#tool-system)
5. [Memory & Context](#memory--context)
6. [Security Model](#security-model)
7. [Cross-Platform Runtime](#cross-platform-runtime)
8. [API Specifications](#api-specifications)

---

## System Components

### Directory Structure

```
mixos-go/
├── build/                          # Build system
│   ├── docker/                     # Docker toolchain
│   ├── patches/                    # Upstream patches
│   └── scripts/                    # Build scripts
│
├── configs/                        # System configurations
│   ├── kernel/                     # Kernel configs
│   └── security/                   # Security hardening
│
├── docs/                           # Documentation
│   ├── VISION.md                   # Project vision
│   ├── ARCHITECTURE.md             # This document
│   ├── API.md                      # API reference
│   └── guides/                     # User guides
│
├── src/                            # Source code
│   ├── mix-cli/                    # Package manager (Go)
│   │   ├── cmd/
│   │   ├── internal/
│   │   └── go.mod
│   │
│   ├── agent-core/                 # Agent system (Go)
│   │   ├── cmd/
│   │   │   └── mixagent/           # Main binary
│   │   ├── internal/
│   │   │   ├── orchestrator/       # Lead agent
│   │   │   ├── agent/              # Agent framework
│   │   │   ├── llm/                # LLM router
│   │   │   ├── tools/              # Tool registry
│   │   │   ├── memory/             # Memory manager
│   │   │   ├── sandbox/            # Execution sandbox
│   │   │   ├── approval/           # Human-in-the-loop
│   │   │   └── config/             # Configuration
│   │   ├── pkg/                    # Public packages
│   │   │   ├── protocol/           # Agent protocol
│   │   │   └── types/              # Shared types
│   │   └── go.mod
│   │
│   ├── agent-python/               # Python AI components
│   │   ├── mixagent/
│   │   │   ├── agents/             # Specialist agents
│   │   │   │   ├── base.py
│   │   │   │   ├── lead.py
│   │   │   │   ├── frontend.py
│   │   │   │   ├── backend.py
│   │   │   │   ├── devops.py
│   │   │   │   ├── security.py
│   │   │   │   ├── qa.py
│   │   │   │   └── docs.py
│   │   │   ├── llm/                # LLM providers
│   │   │   │   ├── base.py
│   │   │   │   ├── ollama.py
│   │   │   │   ├── openai.py
│   │   │   │   ├── anthropic.py
│   │   │   │   ├── google.py
│   │   │   │   └── llamacpp.py
│   │   │   ├── memory/             # Memory systems
│   │   │   ├── reasoning/          # Reasoning engine
│   │   │   └── server.py           # gRPC/HTTP server
│   │   ├── tests/
│   │   ├── pyproject.toml
│   │   └── requirements.txt
│   │
│   ├── runtime/                    # Cross-platform runtime
│   │   ├── termux/
│   │   ├── linux/
│   │   ├── wsl/
│   │   └── macos/
│   │
│   └── packages/                   # System packages
│       ├── base-files/
│       ├── openssh/
│       └── iptables/
│
├── tests/                          # Integration tests
│   ├── e2e/
│   └── benchmarks/
│
├── Makefile                        # Build automation
├── README.md
└── LICENSE
```

---

## Agent System Design

### Agent Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                      AGENT HIERARCHY                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────────┐                          │
│                    │   LEAD AGENT    │                          │
│                    │   (Singleton)   │                          │
│                    └────────┬────────┘                          │
│                             │                                   │
│         Responsibilities:   │                                   │
│         • Project planning  │                                   │
│         • Task delegation   │                                   │
│         • Coordination      │                                   │
│         • Human interface   │                                   │
│                             │                                   │
│    ┌────────────────────────┼────────────────────────┐         │
│    │            │           │           │            │         │
│    ▼            ▼           ▼           ▼            ▼         │
│ ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐         │
│ │Front │   │Back  │   │DevOps│   │  QA  │   │ ...  │         │
│ │ end  │   │ end  │   │      │   │      │   │      │         │
│ └──────┘   └──────┘   └──────┘   └──────┘   └──────┘         │
│                                                                 │
│  SPECIALIST AGENTS (Pool - instantiated as needed)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Agent Base Interface

```go
// Go: internal/agent/agent.go

package agent

import (
    "context"
    "github.com/mixos-go/agent-core/pkg/types"
)

// Agent defines the interface all agents must implement
type Agent interface {
    // Identity
    ID() string
    Name() string
    Role() types.AgentRole
    Capabilities() []types.Capability
    
    // Lifecycle
    Initialize(ctx context.Context, config *Config) error
    Shutdown(ctx context.Context) error
    
    // Task execution
    CanHandle(task *types.Task) bool
    Execute(ctx context.Context, task *types.Task) (*types.Result, error)
    
    // Communication
    ReceiveMessage(msg *types.Message) error
    SendMessage(to string, msg *types.Message) error
    
    // Status
    Status() types.AgentStatus
    Progress() *types.Progress
}

// Config holds agent configuration
type Config struct {
    LLMBackend    string
    MaxTokens     int
    Temperature   float64
    Tools         []string
    ResourceLimit *ResourceLimit
}

// ResourceLimit defines resource constraints
type ResourceLimit struct {
    MaxMemoryMB   int
    MaxCPUPercent int
    MaxDiskMB     int
    TimeoutSec    int
}
```

```python
# Python: mixagent/agents/base.py

from abc import ABC, abstractmethod
from typing import List, Optional, Dict, Any
from dataclasses import dataclass
from enum import Enum

class AgentRole(Enum):
    LEAD = "lead"
    FRONTEND = "frontend"
    BACKEND = "backend"
    DEVOPS = "devops"
    SECURITY = "security"
    QA = "qa"
    DOCS = "docs"
    DATA = "data"
    MOBILE = "mobile"

@dataclass
class Task:
    id: str
    type: str
    description: str
    context: Dict[str, Any]
    dependencies: List[str]
    priority: int
    deadline: Optional[str]

@dataclass
class Result:
    task_id: str
    success: bool
    output: Any
    artifacts: List[str]
    errors: List[str]
    metrics: Dict[str, Any]

class BaseAgent(ABC):
    """Base class for all specialist agents"""
    
    def __init__(self, agent_id: str, config: Dict[str, Any]):
        self.agent_id = agent_id
        self.config = config
        self.llm = None
        self.tools = []
        self.memory = None
    
    @property
    @abstractmethod
    def name(self) -> str:
        pass
    
    @property
    @abstractmethod
    def role(self) -> AgentRole:
        pass
    
    @property
    @abstractmethod
    def capabilities(self) -> List[str]:
        pass
    
    @property
    @abstractmethod
    def system_prompt(self) -> str:
        pass
    
    @abstractmethod
    async def can_handle(self, task: Task) -> bool:
        """Check if agent can handle this task"""
        pass
    
    @abstractmethod
    async def execute(self, task: Task) -> Result:
        """Execute the task"""
        pass
    
    @abstractmethod
    async def plan(self, task: Task) -> List[Task]:
        """Break down task into subtasks"""
        pass
    
    async def collaborate(self, agent_id: str, message: Dict[str, Any]) -> Dict[str, Any]:
        """Send message to another agent"""
        # Implementation via orchestrator
        pass
```

### Lead Agent Implementation

```python
# Python: mixagent/agents/lead.py

from typing import List, Dict, Any, Optional
from .base import BaseAgent, AgentRole, Task, Result
import asyncio

class LeadAgent(BaseAgent):
    """
    Lead Agent - Project Coordinator
    
    Responsibilities:
    - Understand project requirements
    - Create execution plan
    - Delegate to specialist agents
    - Monitor progress
    - Handle conflicts
    - Interface with human
    """
    
    @property
    def name(self) -> str:
        return "Lead Agent"
    
    @property
    def role(self) -> AgentRole:
        return AgentRole.LEAD
    
    @property
    def capabilities(self) -> List[str]:
        return [
            "project_planning",
            "task_decomposition",
            "agent_delegation",
            "progress_monitoring",
            "conflict_resolution",
            "human_communication",
            "quality_assurance"
        ]
    
    @property
    def system_prompt(self) -> str:
        return """You are the Lead Agent, a senior technical project manager 
and architect. Your role is to:

1. UNDERSTAND: Fully comprehend user requirements and project scope
2. PLAN: Create detailed, actionable project plans
3. DELEGATE: Assign tasks to appropriate specialist agents
4. COORDINATE: Ensure agents work together effectively
5. MONITOR: Track progress and identify blockers
6. COMMUNICATE: Keep the human informed and request approvals when needed

You have access to these specialist agents:
- Frontend Agent: UI/UX, React, Vue, CSS, accessibility
- Backend Agent: APIs, databases, authentication, business logic
- DevOps Agent: CI/CD, deployment, infrastructure, monitoring
- Security Agent: Code audit, vulnerability scanning, compliance
- QA Agent: Testing strategy, E2E tests, bug reproduction
- Docs Agent: Documentation, README, API docs

Guidelines:
- Break complex tasks into manageable pieces
- Identify dependencies between tasks
- Set clear checkpoints for human review
- Request approval for destructive or costly operations
- Maintain project context and decisions log
- Resolve conflicts between agents diplomatically
"""
    
    async def can_handle(self, task: Task) -> bool:
        # Lead agent handles coordination tasks
        return task.type in [
            "project_init",
            "planning",
            "coordination",
            "review",
            "approval_request"
        ]
    
    async def execute(self, task: Task) -> Result:
        """Execute coordination task"""
        if task.type == "project_init":
            return await self._init_project(task)
        elif task.type == "planning":
            return await self._create_plan(task)
        elif task.type == "coordination":
            return await self._coordinate(task)
        elif task.type == "review":
            return await self._review(task)
        else:
            return Result(
                task_id=task.id,
                success=False,
                output=None,
                artifacts=[],
                errors=[f"Unknown task type: {task.type}"],
                metrics={}
            )
    
    async def plan(self, task: Task) -> List[Task]:
        """Decompose user request into tasks"""
        
        # Use LLM to analyze and decompose
        analysis = await self.llm.complete(
            system=self.system_prompt,
            prompt=f"""Analyze this user request and create a detailed project plan:

REQUEST: {task.description}

CONTEXT: {task.context}

Create a structured plan with:
1. Project overview
2. Required specialist agents
3. Task breakdown with dependencies
4. Checkpoints for human review
5. Risk assessment

Output as JSON."""
        )
        
        # Parse and create tasks
        plan = self._parse_plan(analysis)
        return self._create_tasks_from_plan(plan)
    
    async def delegate(self, task: Task) -> str:
        """Determine which agent should handle task"""
        
        # Map task types to agents
        agent_mapping = {
            "ui": "frontend",
            "component": "frontend",
            "style": "frontend",
            "api": "backend",
            "database": "backend",
            "auth": "backend",
            "deploy": "devops",
            "ci": "devops",
            "infra": "devops",
            "audit": "security",
            "scan": "security",
            "test": "qa",
            "docs": "docs"
        }
        
        # Use LLM for complex delegation
        for keyword, agent in agent_mapping.items():
            if keyword in task.type.lower():
                return agent
        
        # Fallback to LLM decision
        decision = await self.llm.complete(
            system=self.system_prompt,
            prompt=f"Which specialist agent should handle this task? Task: {task.description}"
        )
        return self._parse_agent_decision(decision)
    
    async def _init_project(self, task: Task) -> Result:
        """Initialize new project"""
        # Create project structure
        # Initialize git repo
        # Set up configuration
        pass
    
    async def _create_plan(self, task: Task) -> Result:
        """Create project execution plan"""
        subtasks = await self.plan(task)
        return Result(
            task_id=task.id,
            success=True,
            output={"plan": subtasks},
            artifacts=[],
            errors=[],
            metrics={"subtask_count": len(subtasks)}
        )
    
    async def _coordinate(self, task: Task) -> Result:
        """Coordinate between agents"""
        pass
    
    async def _review(self, task: Task) -> Result:
        """Review completed work"""
        pass
```

### Specialist Agent Example (Backend)

```python
# Python: mixagent/agents/backend.py

from typing import List, Dict, Any
from .base import BaseAgent, AgentRole, Task, Result

class BackendAgent(BaseAgent):
    """
    Backend Agent - API & Database Specialist
    """
    
    @property
    def name(self) -> str:
        return "Backend Agent"
    
    @property
    def role(self) -> AgentRole:
        return AgentRole.BACKEND
    
    @property
    def capabilities(self) -> List[str]:
        return [
            "api_design",
            "api_implementation",
            "database_design",
            "database_queries",
            "authentication",
            "authorization",
            "business_logic",
            "data_validation",
            "error_handling",
            "performance_optimization"
        ]
    
    @property
    def system_prompt(self) -> str:
        return """You are a Backend Agent, an expert backend engineer specializing in:

- RESTful and GraphQL API design
- Database modeling (SQL and NoSQL)
- Authentication & Authorization (JWT, OAuth, sessions)
- Business logic implementation
- Data validation and sanitization
- Error handling and logging
- Performance optimization
- Security best practices

Languages/Frameworks you excel at:
- Go (Gin, Echo, Fiber)
- Python (FastAPI, Django, Flask)
- Node.js (Express, NestJS)
- Rust (Actix, Axum)

Databases:
- PostgreSQL, MySQL, SQLite
- MongoDB, Redis
- Elasticsearch

Guidelines:
- Write clean, maintainable code
- Follow REST/GraphQL best practices
- Implement proper error handling
- Add input validation
- Consider security implications
- Write efficient database queries
- Document APIs clearly
"""
    
    async def can_handle(self, task: Task) -> bool:
        backend_keywords = [
            "api", "endpoint", "database", "db", "schema",
            "auth", "login", "jwt", "oauth", "session",
            "crud", "query", "migration", "model",
            "backend", "server", "rest", "graphql"
        ]
        task_lower = task.description.lower()
        return any(kw in task_lower for kw in backend_keywords)
    
    async def execute(self, task: Task) -> Result:
        """Execute backend task"""
        
        # Determine specific action
        if "design" in task.type:
            return await self._design_api(task)
        elif "implement" in task.type:
            return await self._implement(task)
        elif "database" in task.type:
            return await self._handle_database(task)
        else:
            return await self._general_backend(task)
    
    async def plan(self, task: Task) -> List[Task]:
        """Break down backend task"""
        
        analysis = await self.llm.complete(
            system=self.system_prompt,
            prompt=f"""Break down this backend task into steps:

TASK: {task.description}

Consider:
1. Database schema changes needed
2. API endpoints to create/modify
3. Business logic implementation
4. Authentication/authorization
5. Testing requirements

Output as JSON list of subtasks."""
        )
        
        return self._parse_subtasks(analysis)
    
    async def _design_api(self, task: Task) -> Result:
        """Design API structure"""
        
        design = await self.llm.complete(
            system=self.system_prompt,
            prompt=f"""Design a REST API for:

{task.description}

Include:
1. Endpoint definitions (method, path, description)
2. Request/response schemas
3. Authentication requirements
4. Error responses

Output as OpenAPI/Swagger YAML."""
        )
        
        # Save to file
        artifact_path = await self.tools.write_file(
            "api-design.yaml",
            design
        )
        
        return Result(
            task_id=task.id,
            success=True,
            output=design,
            artifacts=[artifact_path],
            errors=[],
            metrics={}
        )
    
    async def _implement(self, task: Task) -> Result:
        """Implement backend code"""
        
        # Get context (existing code, requirements)
        context = await self._gather_context(task)
        
        # Generate implementation
        code = await self.llm.complete(
            system=self.system_prompt,
            prompt=f"""Implement the following:

TASK: {task.description}

EXISTING CODE CONTEXT:
{context}

Requirements:
- Follow existing code style
- Add proper error handling
- Include input validation
- Add comments for complex logic

Output the complete implementation."""
        )
        
        # Write files
        artifacts = await self._write_implementation(code)
        
        # Run tests if available
        test_result = await self.tools.run_tests()
        
        return Result(
            task_id=task.id,
            success=test_result.passed,
            output=code,
            artifacts=artifacts,
            errors=test_result.errors,
            metrics={"tests_passed": test_result.passed_count}
        )
```

---

## LLM Backend Architecture

### Router Design

```go
// Go: internal/llm/router.go

package llm

import (
    "context"
    "sync"
)

// Provider represents an LLM provider
type Provider interface {
    Name() string
    Available() bool
    Complete(ctx context.Context, req *Request) (*Response, error)
    Stream(ctx context.Context, req *Request) (<-chan *Chunk, error)
    EstimateCost(req *Request) float64
    EstimateLatency(req *Request) int // milliseconds
}

// Router intelligently routes requests to providers
type Router struct {
    providers map[string]Provider
    config    *RouterConfig
    metrics   *Metrics
    mu        sync.RWMutex
}

// RouterConfig holds routing configuration
type RouterConfig struct {
    DefaultProvider   string
    FallbackProviders []string
    CostLimit         float64 // per request
    LatencyTarget     int     // milliseconds
    PreferLocal       bool
    
    // Routing rules
    Rules []RoutingRule
}

// RoutingRule defines when to use specific provider
type RoutingRule struct {
    Condition   string // e.g., "complexity > 0.8"
    Provider    string
    Priority    int
}

// Route selects the best provider for a request
func (r *Router) Route(ctx context.Context, req *Request) (Provider, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    // Analyze request
    analysis := r.analyzeRequest(req)
    
    // Apply routing rules
    for _, rule := range r.config.Rules {
        if r.matchRule(rule, analysis) {
            if provider, ok := r.providers[rule.Provider]; ok && provider.Available() {
                return provider, nil
            }
        }
    }
    
    // Cost-based routing
    if r.config.CostLimit > 0 {
        provider := r.selectByCost(req)
        if provider != nil {
            return provider, nil
        }
    }
    
    // Latency-based routing
    if r.config.LatencyTarget > 0 {
        provider := r.selectByLatency(req)
        if provider != nil {
            return provider, nil
        }
    }
    
    // Prefer local if configured
    if r.config.PreferLocal {
        if local := r.getLocalProvider(); local != nil && local.Available() {
            return local, nil
        }
    }
    
    // Default provider
    if provider, ok := r.providers[r.config.DefaultProvider]; ok {
        return provider, nil
    }
    
    // Fallback chain
    for _, name := range r.config.FallbackProviders {
        if provider, ok := r.providers[name]; ok && provider.Available() {
            return provider, nil
        }
    }
    
    return nil, ErrNoAvailableProvider
}

// analyzeRequest determines request characteristics
func (r *Router) analyzeRequest(req *Request) *RequestAnalysis {
    return &RequestAnalysis{
        TokenCount:    estimateTokens(req.Prompt),
        Complexity:    estimateComplexity(req.Prompt),
        RequiresCode:  containsCodeRequest(req.Prompt),
        RequiresLarge: req.MaxTokens > 4096,
    }
}
```

### Provider Implementations

```python
# Python: mixagent/llm/ollama.py

from typing import AsyncIterator, Optional, Dict, Any
from .base import LLMProvider, Request, Response, Chunk
import httpx

class OllamaProvider(LLMProvider):
    """Local Ollama LLM provider"""
    
    def __init__(self, config: Dict[str, Any]):
        self.base_url = config.get("base_url", "http://localhost:11434")
        self.model = config.get("model", "qwen2.5-coder:7b")
        self.client = httpx.AsyncClient(timeout=300)
    
    @property
    def name(self) -> str:
        return "ollama"
    
    async def available(self) -> bool:
        try:
            resp = await self.client.get(f"{self.base_url}/api/tags")
            return resp.status_code == 200
        except:
            return False
    
    async def complete(self, request: Request) -> Response:
        payload = {
            "model": self.model,
            "prompt": request.prompt,
            "system": request.system,
            "stream": False,
            "options": {
                "temperature": request.temperature,
                "num_predict": request.max_tokens,
            }
        }
        
        resp = await self.client.post(
            f"{self.base_url}/api/generate",
            json=payload
        )
        data = resp.json()
        
        return Response(
            content=data["response"],
            model=self.model,
            provider=self.name,
            usage={
                "prompt_tokens": data.get("prompt_eval_count", 0),
                "completion_tokens": data.get("eval_count", 0),
            }
        )
    
    async def stream(self, request: Request) -> AsyncIterator[Chunk]:
        payload = {
            "model": self.model,
            "prompt": request.prompt,
            "system": request.system,
            "stream": True,
        }
        
        async with self.client.stream(
            "POST",
            f"{self.base_url}/api/generate",
            json=payload
        ) as resp:
            async for line in resp.aiter_lines():
                if line:
                    data = json.loads(line)
                    yield Chunk(
                        content=data.get("response", ""),
                        done=data.get("done", False)
                    )
    
    def estimate_cost(self, request: Request) -> float:
        # Local = free
        return 0.0
    
    def estimate_latency(self, request: Request) -> int:
        # Estimate based on model size and tokens
        tokens = len(request.prompt.split()) * 1.3
        # ~50 tokens/sec for 7B model on decent hardware
        return int((tokens / 50) * 1000)
```

```python
# Python: mixagent/llm/anthropic.py

from typing import AsyncIterator, Dict, Any
from .base import LLMProvider, Request, Response, Chunk
import anthropic

class AnthropicProvider(LLMProvider):
    """Anthropic Claude API provider"""
    
    def __init__(self, config: Dict[str, Any]):
        self.api_key = config.get("api_key")
        self.model = config.get("model", "claude-3-5-sonnet-20241022")
        self.client = anthropic.AsyncAnthropic(api_key=self.api_key)
    
    @property
    def name(self) -> str:
        return "anthropic"
    
    async def available(self) -> bool:
        return self.api_key is not None
    
    async def complete(self, request: Request) -> Response:
        message = await self.client.messages.create(
            model=self.model,
            max_tokens=request.max_tokens,
            system=request.system,
            messages=[
                {"role": "user", "content": request.prompt}
            ]
        )
        
        return Response(
            content=message.content[0].text,
            model=self.model,
            provider=self.name,
            usage={
                "prompt_tokens": message.usage.input_tokens,
                "completion_tokens": message.usage.output_tokens,
            }
        )
    
    async def stream(self, request: Request) -> AsyncIterator[Chunk]:
        async with self.client.messages.stream(
            model=self.model,
            max_tokens=request.max_tokens,
            system=request.system,
            messages=[
                {"role": "user", "content": request.prompt}
            ]
        ) as stream:
            async for text in stream.text_stream:
                yield Chunk(content=text, done=False)
            yield Chunk(content="", done=True)
    
    def estimate_cost(self, request: Request) -> float:
        # Claude 3.5 Sonnet pricing (as of 2024)
        input_cost = 0.003 / 1000  # per token
        output_cost = 0.015 / 1000
        
        est_input = len(request.prompt.split()) * 1.3
        est_output = request.max_tokens * 0.5  # assume 50% usage
        
        return (est_input * input_cost) + (est_output * output_cost)
    
    def estimate_latency(self, request: Request) -> int:
        # Cloud API ~100-500ms base + generation time
        return 300 + int(request.max_tokens * 0.5 * 20)  # ~50 tokens/sec
```

---

## Tool System

### Tool Registry

```go
// Go: internal/tools/registry.go

package tools

import (
    "context"
    "sync"
)

// Tool defines the interface for agent tools
type Tool interface {
    Name() string
    Description() string
    Parameters() []Parameter
    Execute(ctx context.Context, params map[string]interface{}) (*Result, error)
    RequiresApproval() bool
    RiskLevel() RiskLevel
}

type RiskLevel int

const (
    RiskLow RiskLevel = iota
    RiskMedium
    RiskHigh
    RiskCritical
)

// Registry manages available tools
type Registry struct {
    tools map[string]Tool
    mu    sync.RWMutex
}

func NewRegistry() *Registry {
    r := &Registry{
        tools: make(map[string]Tool),
    }
    
    // Register built-in tools
    r.Register(&ShellTool{})
    r.Register(&FileReadTool{})
    r.Register(&FileWriteTool{})
    r.Register(&GitTool{})
    r.Register(&BrowserTool{})
    r.Register(&DockerTool{})
    
    return r
}

func (r *Registry) Register(tool Tool) {
    r.mu.Lock()
    defer r.mu.Unlock()
    r.tools[tool.Name()] = tool
}

func (r *Registry) Get(name string) (Tool, bool) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    tool, ok := r.tools[name]
    return tool, ok
}

func (r *Registry) List() []Tool {
    r.mu.RLock()
    defer r.mu.RUnlock()
    
    tools := make([]Tool, 0, len(r.tools))
    for _, t := range r.tools {
        tools = append(tools, t)
    }
    return tools
}
```

### Tool Implementations

```go
// Go: internal/tools/shell.go

package tools

import (
    "context"
    "os/exec"
    "time"
)

type ShellTool struct {
    workDir string
    timeout time.Duration
}

func (t *ShellTool) Name() string {
    return "shell"
}

func (t *ShellTool) Description() string {
    return "Execute shell commands in a sandboxed environment"
}

func (t *ShellTool) Parameters() []Parameter {
    return []Parameter{
        {Name: "command", Type: "string", Required: true, Description: "Command to execute"},
        {Name: "workdir", Type: "string", Required: false, Description: "Working directory"},
        {Name: "timeout", Type: "int", Required: false, Description: "Timeout in seconds"},
    }
}

func (t *ShellTool) Execute(ctx context.Context, params map[string]interface{}) (*Result, error) {
    command := params["command"].(string)
    
    // Create sandboxed execution context
    cmd := exec.CommandContext(ctx, "sh", "-c", command)
    cmd.Dir = t.workDir
    
    output, err := cmd.CombinedOutput()
    
    return &Result{
        Success: err == nil,
        Output:  string(output),
        Error:   err,
    }, nil
}

func (t *ShellTool) RequiresApproval() bool {
    return false // Basic shell doesn't require approval
}

func (t *ShellTool) RiskLevel() RiskLevel {
    return RiskMedium
}
```

```go
// Go: internal/tools/git.go

package tools

import (
    "context"
    "os/exec"
)

type GitTool struct {
    repoPath string
}

func (t *GitTool) Name() string {
    return "git"
}

func (t *GitTool) Description() string {
    return "Git version control operations"
}

func (t *GitTool) Parameters() []Parameter {
    return []Parameter{
        {Name: "operation", Type: "string", Required: true, 
         Description: "Git operation: clone, commit, push, pull, branch, status, diff"},
        {Name: "args", Type: "array", Required: false, Description: "Additional arguments"},
    }
}

func (t *GitTool) Execute(ctx context.Context, params map[string]interface{}) (*Result, error) {
    operation := params["operation"].(string)
    args := []string{operation}
    
    if extraArgs, ok := params["args"].([]interface{}); ok {
        for _, arg := range extraArgs {
            args = append(args, arg.(string))
        }
    }
    
    cmd := exec.CommandContext(ctx, "git", args...)
    cmd.Dir = t.repoPath
    
    output, err := cmd.CombinedOutput()
    
    return &Result{
        Success: err == nil,
        Output:  string(output),
        Error:   err,
    }, nil
}

func (t *GitTool) RequiresApproval() bool {
    return false // Most git ops are safe
}

func (t *GitTool) RiskLevel() RiskLevel {
    return RiskLow
}
```

---

## Memory & Context

### Memory Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    MEMORY SYSTEM                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SHORT-TERM MEMORY                          │   │
│  │              (Session Context)                          │   │
│  │                                                         │   │
│  │  • Current conversation                                 │   │
│  │  • Active task context                                  │   │
│  │  • Recent tool outputs                                  │   │
│  │  • Working files                                        │   │
│  │                                                         │   │
│  │  Storage: In-memory                                     │   │
│  │  Lifetime: Session                                      │   │
│  │  Size: Limited by context window                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              LONG-TERM MEMORY                           │   │
│  │              (Project Knowledge)                        │   │
│  │                                                         │   │
│  │  • Project structure                                    │   │
│  │  • Code summaries                                       │   │
│  │  • Decisions made                                       │   │
│  │  • User preferences                                     │   │
│  │                                                         │   │
│  │  Storage: SQLite + Vector DB                            │   │
│  │  Lifetime: Persistent                                   │   │
│  │  Retrieval: Semantic search                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              EPISODIC MEMORY                            │   │
│  │              (Learnings)                                │   │
│  │                                                         │   │
│  │  • Successful patterns                                  │   │
│  │  • Failed approaches                                    │   │
│  │  • User feedback                                        │   │
│  │  • Performance metrics                                  │   │
│  │                                                         │   │
│  │  Storage: Vector DB                                     │   │
│  │  Lifetime: Persistent                                   │   │
│  │  Usage: Improve future decisions                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Memory Implementation

```python
# Python: mixagent/memory/manager.py

from typing import List, Dict, Any, Optional
from dataclasses import dataclass
import sqlite3
import json

@dataclass
class MemoryEntry:
    id: str
    type: str  # short_term, long_term, episodic
    content: str
    metadata: Dict[str, Any]
    embedding: Optional[List[float]]
    timestamp: str

class MemoryManager:
    """Manages agent memory across sessions"""
    
    def __init__(self, db_path: str, embedding_model: str = "all-MiniLM-L6-v2"):
        self.db_path = db_path
        self.conn = sqlite3.connect(db_path)
        self._init_db()
        
        # Initialize embedding model for semantic search
        from sentence_transformers import SentenceTransformer
        self.embedder = SentenceTransformer(embedding_model)
    
    def _init_db(self):
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                type TEXT,
                content TEXT,
                metadata TEXT,
                embedding BLOB,
                timestamp TEXT
            )
        """)
        self.conn.execute("""
            CREATE INDEX IF NOT EXISTS idx_type ON memories(type)
        """)
        self.conn.commit()
    
    def store(self, entry: MemoryEntry) -> None:
        """Store a memory entry"""
        # Generate embedding if not provided
        if entry.embedding is None:
            entry.embedding = self.embedder.encode(entry.content).tolist()
        
        self.conn.execute(
            """INSERT OR REPLACE INTO memories 
               (id, type, content, metadata, embedding, timestamp)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                entry.id,
                entry.type,
                entry.content,
                json.dumps(entry.metadata),
                json.dumps(entry.embedding),
                entry.timestamp
            )
        )
        self.conn.commit()
    
    def retrieve(self, query: str, type: Optional[str] = None, limit: int = 5) -> List[MemoryEntry]:
        """Retrieve relevant memories using semantic search"""
        query_embedding = self.embedder.encode(query)
        
        # Get all memories of specified type
        if type:
            cursor = self.conn.execute(
                "SELECT * FROM memories WHERE type = ?", (type,)
            )
        else:
            cursor = self.conn.execute("SELECT * FROM memories")
        
        # Calculate similarity and rank
        results = []
        for row in cursor:
            entry_embedding = json.loads(row[4])
            similarity = self._cosine_similarity(query_embedding, entry_embedding)
            results.append((similarity, MemoryEntry(
                id=row[0],
                type=row[1],
                content=row[2],
                metadata=json.loads(row[3]),
                embedding=entry_embedding,
                timestamp=row[5]
            )))
        
        # Sort by similarity and return top results
        results.sort(key=lambda x: x[0], reverse=True)
        return [entry for _, entry in results[:limit]]
    
    def _cosine_similarity(self, a: List[float], b: List[float]) -> float:
        import numpy as np
        a, b = np.array(a), np.array(b)
        return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
    
    def get_context(self, task_id: str) -> Dict[str, Any]:
        """Get full context for a task"""
        return {
            "short_term": self.retrieve(task_id, type="short_term", limit=10),
            "long_term": self.retrieve(task_id, type="long_term", limit=5),
            "episodic": self.retrieve(task_id, type="episodic", limit=3),
        }
```

---

## Security Model

### Approval System

```go
// Go: internal/approval/gateway.go

package approval

import (
    "context"
    "time"
)

type RiskLevel int

const (
    RiskNone RiskLevel = iota
    RiskLow
    RiskMedium
    RiskHigh
    RiskCritical
)

// Action represents an action requiring potential approval
type Action struct {
    ID          string
    Type        string
    Description string
    Agent       string
    RiskLevel   RiskLevel
    Parameters  map[string]interface{}
    Timestamp   time.Time
}

// Decision represents human decision on an action
type Decision struct {
    ActionID  string
    Approved  bool
    Comment   string
    Timestamp time.Time
}

// Gateway manages human-in-the-loop approvals
type Gateway struct {
    config    *Config
    pending   map[string]*Action
    decisions chan *Decision
}

type Config struct {
    AutoApproveLevel RiskLevel // Auto-approve below this level
    TimeoutSeconds   int       // Timeout for approval requests
    
    // Actions that always require approval
    AlwaysApprove []string
    
    // Actions that never require approval
    NeverApprove []string
}

func (g *Gateway) RequestApproval(ctx context.Context, action *Action) (*Decision, error) {
    // Check if auto-approve
    if g.shouldAutoApprove(action) {
        return &Decision{
            ActionID: action.ID,
            Approved: true,
            Comment:  "Auto-approved (low risk)",
        }, nil
    }
    
    // Check if always blocked
    if g.shouldBlock(action) {
        return &Decision{
            ActionID: action.ID,
            Approved: false,
            Comment:  "Blocked by policy",
        }, nil
    }
    
    // Request human approval
    g.pending[action.ID] = action
    
    // Notify human (via TUI, webhook, etc.)
    g.notifyHuman(action)
    
    // Wait for decision or timeout
    select {
    case decision := <-g.decisions:
        if decision.ActionID == action.ID {
            delete(g.pending, action.ID)
            return decision, nil
        }
    case <-time.After(time.Duration(g.config.TimeoutSeconds) * time.Second):
        delete(g.pending, action.ID)
        return nil, ErrApprovalTimeout
    case <-ctx.Done():
        delete(g.pending, action.ID)
        return nil, ctx.Err()
    }
    
    return nil, ErrUnexpected
}

func (g *Gateway) shouldAutoApprove(action *Action) bool {
    // Check risk level
    if action.RiskLevel < g.config.AutoApproveLevel {
        return true
    }
    
    // Check never-approve list
    for _, blocked := range g.config.NeverApprove {
        if action.Type == blocked {
            return false
        }
    }
    
    return false
}
```

### Sandbox Execution

```go
// Go: internal/sandbox/sandbox.go

package sandbox

import (
    "context"
    "os"
    "os/exec"
    "syscall"
)

// Sandbox provides isolated execution environment
type Sandbox struct {
    rootDir   string
    config    *Config
}

type Config struct {
    // Filesystem
    ReadOnlyPaths  []string
    WritablePaths  []string
    HiddenPaths    []string
    
    // Resources
    MaxMemoryMB    int
    MaxCPUPercent  int
    MaxDiskMB      int
    MaxProcesses   int
    
    // Network
    NetworkEnabled bool
    AllowedHosts   []string
    
    // Time
    MaxRuntimeSec  int
}

func (s *Sandbox) Execute(ctx context.Context, cmd string, args []string) (*Result, error) {
    // Create isolated environment
    env := s.createEnvironment()
    
    // Set up command with restrictions
    c := exec.CommandContext(ctx, cmd, args...)
    c.Dir = s.rootDir
    c.Env = env
    
    // Apply resource limits (Linux-specific)
    c.SysProcAttr = &syscall.SysProcAttr{
        Cloneflags: syscall.CLONE_NEWNS | syscall.CLONE_NEWPID,
    }
    
    // Execute
    output, err := c.CombinedOutput()
    
    return &Result{
        Output:   string(output),
        ExitCode: c.ProcessState.ExitCode(),
        Error:    err,
    }, nil
}

func (s *Sandbox) createEnvironment() []string {
    return []string{
        "PATH=/usr/local/bin:/usr/bin:/bin",
        "HOME=" + s.rootDir,
        "TERM=xterm-256color",
        "LANG=C.UTF-8",
        // Restrict environment
        "MIXOS_SANDBOX=1",
    }
}
```

---

## Cross-Platform Runtime

### Runtime Abstraction

```go
// Go: internal/runtime/runtime.go

package runtime

import (
    "context"
    "runtime"
)

// Runtime provides platform-specific functionality
type Runtime interface {
    // Platform info
    Platform() string
    Arch() string
    
    // Filesystem
    RootPath() string
    TempPath() string
    
    // Process management
    Execute(ctx context.Context, cmd string, args []string) (*Result, error)
    
    // Resource monitoring
    MemoryUsage() uint64
    CPUUsage() float64
    DiskUsage() uint64
    
    // Capabilities
    HasDocker() bool
    HasGPU() bool
    MaxMemory() uint64
}

// Detect returns the appropriate runtime for current platform
func Detect() Runtime {
    switch runtime.GOOS {
    case "linux":
        if isTermux() {
            return &TermuxRuntime{}
        }
        if isWSL() {
            return &WSLRuntime{}
        }
        return &LinuxRuntime{}
    case "darwin":
        return &MacOSRuntime{}
    case "windows":
        return &WindowsRuntime{}
    default:
        return &GenericRuntime{}
    }
}

func isTermux() bool {
    // Check for Termux-specific paths/env
    _, err := os.Stat("/data/data/com.termux")
    return err == nil
}

func isWSL() bool {
    // Check for WSL
    data, err := os.ReadFile("/proc/version")
    if err != nil {
        return false
    }
    return strings.Contains(string(data), "microsoft") ||
           strings.Contains(string(data), "WSL")
}
```

### Termux Runtime

```go
// Go: internal/runtime/termux.go

package runtime

import (
    "context"
    "os"
    "os/exec"
)

type TermuxRuntime struct {
    prefix string
}

func (r *TermuxRuntime) Platform() string {
    return "termux"
}

func (r *TermuxRuntime) Arch() string {
    return runtime.GOARCH // Usually arm64
}

func (r *TermuxRuntime) RootPath() string {
    return os.Getenv("PREFIX") // /data/data/com.termux/files/usr
}

func (r *TermuxRuntime) TempPath() string {
    return os.Getenv("TMPDIR") // /data/data/com.termux/files/usr/tmp
}

func (r *TermuxRuntime) Execute(ctx context.Context, cmd string, args []string) (*Result, error) {
    // Use proot for commands requiring different root
    if r.needsProot(cmd) {
        return r.executeWithProot(ctx, cmd, args)
    }
    
    c := exec.CommandContext(ctx, cmd, args...)
    output, err := c.CombinedOutput()
    
    return &Result{
        Output:   string(output),
        ExitCode: c.ProcessState.ExitCode(),
        Error:    err,
    }, nil
}

func (r *TermuxRuntime) executeWithProot(ctx context.Context, cmd string, args []string) (*Result, error) {
    prootArgs := []string{
        "-0",           // Fake root
        "-r", r.RootPath(),
        "-b", "/dev",
        "-b", "/proc",
        "-b", "/sys",
        cmd,
    }
    prootArgs = append(prootArgs, args...)
    
    c := exec.CommandContext(ctx, "proot", prootArgs...)
    output, err := c.CombinedOutput()
    
    return &Result{
        Output:   string(output),
        ExitCode: c.ProcessState.ExitCode(),
        Error:    err,
    }, nil
}

func (r *TermuxRuntime) HasDocker() bool {
    return false // Docker not available on Termux
}

func (r *TermuxRuntime) HasGPU() bool {
    return false // GPU compute not available
}

func (r *TermuxRuntime) MaxMemory() uint64 {
    // Typically limited on Android
    return 2 * 1024 * 1024 * 1024 // 2GB default assumption
}
```

---

## API Specifications

### Agent Communication Protocol

```protobuf
// proto/agent.proto

syntax = "proto3";

package mixagent;

service AgentService {
    // Task management
    rpc SubmitTask(Task) returns (TaskResponse);
    rpc GetTaskStatus(TaskID) returns (TaskStatus);
    rpc CancelTask(TaskID) returns (CancelResponse);
    
    // Agent communication
    rpc SendMessage(AgentMessage) returns (MessageResponse);
    rpc StreamMessages(AgentID) returns (stream AgentMessage);
    
    // Approval workflow
    rpc RequestApproval(ApprovalRequest) returns (ApprovalResponse);
    rpc SubmitDecision(Decision) returns (DecisionResponse);
}

message Task {
    string id = 1;
    string type = 2;
    string description = 3;
    map<string, string> context = 4;
    repeated string dependencies = 5;
    int32 priority = 6;
}

message TaskResponse {
    string task_id = 1;
    bool accepted = 2;
    string message = 3;
}

message AgentMessage {
    string from_agent = 1;
    string to_agent = 2;
    string type = 3;
    bytes payload = 4;
    int64 timestamp = 5;
}

message ApprovalRequest {
    string action_id = 1;
    string action_type = 2;
    string description = 3;
    string agent = 4;
    int32 risk_level = 5;
    map<string, string> parameters = 6;
}

message Decision {
    string action_id = 1;
    bool approved = 2;
    string comment = 3;
}
```

### REST API

```yaml
# openapi.yaml

openapi: 3.0.0
info:
  title: MixOS-GO Agent API
  version: 1.0.0

paths:
  /api/v1/tasks:
    post:
      summary: Submit a new task
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Task'
      responses:
        '201':
          description: Task created
          
  /api/v1/tasks/{taskId}:
    get:
      summary: Get task status
      parameters:
        - name: taskId
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Task status
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TaskStatus'

  /api/v1/agents:
    get:
      summary: List available agents
      responses:
        '200':
          description: Agent list
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Agent'

  /api/v1/approvals/pending:
    get:
      summary: Get pending approvals
      responses:
        '200':
          description: Pending approvals
          
  /api/v1/approvals/{actionId}:
    post:
      summary: Submit approval decision
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Decision'

components:
  schemas:
    Task:
      type: object
      properties:
        type:
          type: string
        description:
          type: string
        context:
          type: object
        priority:
          type: integer
          
    TaskStatus:
      type: object
      properties:
        id:
          type: string
        status:
          type: string
          enum: [pending, running, completed, failed]
        progress:
          type: number
        result:
          type: object
          
    Agent:
      type: object
      properties:
        id:
          type: string
        name:
          type: string
        role:
          type: string
        status:
          type: string
        capabilities:
          type: array
          items:
            type: string
            
    Decision:
      type: object
      properties:
        approved:
          type: boolean
        comment:
          type: string
```

---

## Appendix

### Configuration File Format

```yaml
# ~/.mixos/config.yaml

# Runtime configuration
runtime:
  profile: standard  # minimal, standard, performance
  data_dir: ~/.mixos/data
  log_level: info

# LLM configuration
llm:
  default_provider: ollama
  prefer_local: true
  cost_limit: 1.0  # USD per session
  
  providers:
    ollama:
      enabled: true
      base_url: http://localhost:11434
      model: qwen2.5-coder:7b
      
    anthropic:
      enabled: true
      api_key: ${ANTHROPIC_API_KEY}
      model: claude-3-5-sonnet-20241022
      
    openai:
      enabled: false
      api_key: ${OPENAI_API_KEY}
      model: gpt-4-turbo

# Agent configuration
agents:
  lead:
    enabled: true
    llm_provider: anthropic  # Use best model for lead
    
  specialists:
    frontend:
      enabled: true
      llm_provider: ollama
    backend:
      enabled: true
      llm_provider: ollama
    devops:
      enabled: true
      llm_provider: ollama

# Approval configuration
approval:
  auto_approve_level: low  # none, low, medium
  timeout_seconds: 300
  
  always_approve:
    - deploy_production
    - delete_files
    - api_key_usage
    
  never_approve:
    - read_file
    - list_directory
    - git_status

# Security configuration
security:
  sandbox_enabled: true
  network_restricted: false
  allowed_hosts:
    - github.com
    - api.anthropic.com
    - api.openai.com
```

---

*Document Version: 1.0.0*
*Last Updated: 2026-01-03*

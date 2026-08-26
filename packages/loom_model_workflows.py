"""Policy gateway between Casita and n8n's workflow-builder MCP tools.

The gateway deliberately exposes only draft authoring operations.  n8n's MCP
credential never leaves Loom, protected personal workflows are filtered from
read results and rejected before every mutation, and publication/execution are
not part of the allow-list.
"""

from __future__ import annotations

import argparse
import hmac
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import itertools
import json
import logging
import os
from pathlib import Path
import re
import threading
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


LOGGER = logging.getLogger("loom-model-workflows")

DEFAULT_PROTECTED_IDS = {
    "ThornEveningDrop",
    "ThornFrictionToFix",
    "ThornMorningOperatorBrief",
    "ThornNightBrainDump",
    "ThornRestartCapsule",
}
DEFAULT_PROTECTED_NAMES = {
    "Thorn | Evening drop",
    "Thorn | Friction-to-fix pipeline",
    "Thorn | Morning operator brief",
    "Thorn | Night brain dump",
    "Thorn | Restart capsule",
}
DEFAULT_PROTECTED_TAGS = {"personal", "protected", "casita-protected"}
DEFAULT_PROTECTED_PREFIXES = {"thorn |"}

READ_TOOLS = {
    "search_workflows",
    "get_workflow_details",
    "get_workflow_sdk_reference",
    "search_nodes",
    "get_node_types",
    "validate_workflow",
}
WRITE_TOOLS = {
    "create_workflow_from_code",
    "update_workflow",
    "archive_workflow",
}
ALLOWED_TOOLS = READ_TOOLS | WRITE_TOOLS

MAX_REQUEST_BYTES = 96 * 1024
MAX_UPSTREAM_BYTES = 2 * 1024 * 1024
MAX_CODE_LENGTH = 48_000
MAX_UPDATE_OPERATIONS = 40
MAX_SEARCH_QUERIES = 4

WORKFLOW_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


class GatewayError(Exception):
    """A bounded error safe to return to the Home Assistant tool."""

    def __init__(self, status: HTTPStatus, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def normalized(value: Any) -> str:
    """Normalize an n8n name or tag for exact policy comparisons."""
    return " ".join(str(value or "").casefold().split())


def json_object(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise GatewayError(HTTPStatus.BAD_REQUEST, f"{label} must be an object")
    return value


def bounded_string(
    value: Any,
    label: str,
    *,
    required: bool = False,
    maximum: int = 1_000,
) -> str:
    if value is None:
        value = ""
    if not isinstance(value, str):
        raise GatewayError(HTTPStatus.BAD_REQUEST, f"{label} must be a string")
    result = value.strip() if maximum < MAX_CODE_LENGTH else value
    if required and not result:
        raise GatewayError(HTTPStatus.BAD_REQUEST, f"{label} is required")
    if len(result) > maximum:
        raise GatewayError(
            HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
            f"{label} exceeds {maximum} characters",
        )
    return result


def bounded_integer(
    value: Any,
    label: str,
    *,
    minimum: int,
    maximum: int,
) -> int:
    if isinstance(value, bool):
        raise GatewayError(HTTPStatus.BAD_REQUEST, f"{label} must be an integer")
    try:
        result = int(value)
    except (TypeError, ValueError) as error:
        raise GatewayError(
            HTTPStatus.BAD_REQUEST, f"{label} must be an integer"
        ) from error
    return max(minimum, min(maximum, result))


class WorkflowPolicy:
    """Identify workflows that no model operation may inspect or mutate."""

    def __init__(
        self,
        protected_ids: set[str] | None = None,
        protected_names: set[str] | None = None,
        protected_tags: set[str] | None = None,
        protected_prefixes: set[str] | None = None,
    ) -> None:
        self.protected_ids = set(protected_ids or DEFAULT_PROTECTED_IDS)
        self.protected_names = {
            normalized(name) for name in (protected_names or DEFAULT_PROTECTED_NAMES)
        }
        self.protected_tags = {
            normalized(tag) for tag in (protected_tags or DEFAULT_PROTECTED_TAGS)
        }
        self.protected_prefixes = {
            normalized(prefix)
            for prefix in (protected_prefixes or DEFAULT_PROTECTED_PREFIXES)
        }

    @classmethod
    def from_environment(cls) -> "WorkflowPolicy":
        def values(name: str) -> set[str]:
            return {
                item.strip()
                for item in os.getenv(name, "").split(",")
                if item.strip()
            }

        return cls(
            protected_ids=DEFAULT_PROTECTED_IDS
            | values("LOOM_MODEL_PROTECTED_IDS"),
            protected_names=DEFAULT_PROTECTED_NAMES
            | values("LOOM_MODEL_PROTECTED_NAMES"),
            protected_tags=DEFAULT_PROTECTED_TAGS
            | values("LOOM_MODEL_PROTECTED_TAGS"),
            protected_prefixes=DEFAULT_PROTECTED_PREFIXES
            | values("LOOM_MODEL_PROTECTED_PREFIXES"),
        )

    def is_protected(self, workflow: dict[str, Any]) -> bool:
        workflow_id = str(workflow.get("id") or "")
        if workflow_id in self.protected_ids:
            return True
        workflow_name = normalized(workflow.get("name"))
        if workflow_name in self.protected_names or any(
            workflow_name.startswith(prefix) for prefix in self.protected_prefixes
        ):
            return True
        tags = workflow.get("tags") or []
        for tag in tags:
            tag_name = tag.get("name") if isinstance(tag, dict) else tag
            if normalized(tag_name) in self.protected_tags:
                return True
        return False

    def reject_reserved_name(self, name: Any) -> None:
        workflow_name = normalized(name)
        if workflow_name in self.protected_names or any(
            workflow_name.startswith(prefix) for prefix in self.protected_prefixes
        ):
            raise GatewayError(
                HTTPStatus.FORBIDDEN,
                "That workflow name is reserved for a protected personal workflow",
            )


class McpClient:
    """Small stateless Streamable HTTP client for n8n's local MCP endpoint."""

    def __init__(self, url: str, token_file: Path, timeout: float = 45.0) -> None:
        self.url = url
        self.token_file = token_file
        self.timeout = timeout
        self._ids = itertools.count(1)
        self._id_lock = threading.Lock()

    def _token(self) -> str:
        try:
            token = self.token_file.read_text(encoding="utf-8").strip()
        except OSError as error:
            raise GatewayError(
                HTTPStatus.SERVICE_UNAVAILABLE,
                "The local n8n model credential is unavailable",
            ) from error
        if not token or token.count(".") != 2:
            raise GatewayError(
                HTTPStatus.SERVICE_UNAVAILABLE,
                "The local n8n model credential is malformed",
            )
        return token

    def call(self, tool: str, arguments: dict[str, Any]) -> dict[str, Any]:
        with self._id_lock:
            request_id = next(self._ids)
        body = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": "tools/call",
                "params": {"name": tool, "arguments": arguments},
            },
            separators=(",", ":"),
        ).encode("utf-8")
        request = Request(
            self.url,
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {self._token()}",
                "Accept": "application/json, text/event-stream",
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read(MAX_UPSTREAM_BYTES + 1)
        except HTTPError as error:
            LOGGER.warning("n8n MCP returned HTTP %s", error.code)
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n rejected the bounded workflow request",
            ) from error
        except (TimeoutError, URLError, OSError) as error:
            LOGGER.warning("n8n MCP request failed: %s", type(error).__name__)
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n's workflow builder is temporarily unavailable",
            ) from error

        if len(raw) > MAX_UPSTREAM_BYTES:
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n returned an unexpectedly large workflow response",
            )
        payload = self._decode_response(raw)
        if payload.get("error"):
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n's workflow builder rejected the request",
            )
        result = payload.get("result")
        if not isinstance(result, dict):
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n returned an invalid workflow response",
            )
        structured = result.get("structuredContent")
        if isinstance(structured, dict):
            output = structured
        else:
            output = self._content_result(result.get("content"))
        if result.get("isError"):
            message = str(output.get("error") or "n8n rejected the workflow request")
            return {"ok": False, "error": message, "result": output}
        return {"ok": True, "result": output}

    @staticmethod
    def _decode_response(raw: bytes) -> dict[str, Any]:
        text = raw.decode("utf-8", errors="replace")
        candidates = [
            line[6:].strip()
            for line in text.splitlines()
            if line.startswith("data: ")
        ]
        if not candidates:
            candidates = [text.strip()]
        for candidate in reversed(candidates):
            try:
                value = json.loads(candidate)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                return value
        raise GatewayError(
            HTTPStatus.BAD_GATEWAY,
            "n8n returned an unreadable workflow response",
        )

    @staticmethod
    def _content_result(content: Any) -> dict[str, Any]:
        if not isinstance(content, list):
            return {"value": content}
        text_parts = [
            str(item.get("text"))
            for item in content
            if isinstance(item, dict) and item.get("type") == "text"
        ]
        combined = "\n".join(text_parts)
        try:
            parsed = json.loads(combined)
        except json.JSONDecodeError:
            return {"text": combined}
        return parsed if isinstance(parsed, dict) else {"value": parsed}


class WorkflowGateway:
    """Validate tool arguments and enforce personal-workflow protection."""

    def __init__(self, client: McpClient, policy: WorkflowPolicy) -> None:
        self.client = client
        self.policy = policy

    def health(self) -> dict[str, Any]:
        return {
            "status": "healthy",
            "mode": "draft-only",
            "protected_workflows": len(self.policy.protected_ids),
            "allowed_tools": sorted(ALLOWED_TOOLS),
        }

    def handle(self, payload: dict[str, Any]) -> dict[str, Any]:
        tool = bounded_string(payload.get("tool"), "tool", required=True, maximum=64)
        if tool not in ALLOWED_TOOLS:
            raise GatewayError(
                HTTPStatus.FORBIDDEN,
                "That n8n operation is not available to the voice model",
            )
        arguments = json_object(payload.get("arguments", {}), "arguments")

        if tool == "search_workflows":
            return self._search(arguments)
        if tool == "get_workflow_details":
            return self._details(arguments)
        if tool == "get_workflow_sdk_reference":
            return self._reference(arguments)
        if tool == "search_nodes":
            return self._search_nodes(arguments)
        if tool == "get_node_types":
            return self._node_types(arguments)
        if tool == "validate_workflow":
            return self._validate(arguments)
        if tool == "create_workflow_from_code":
            return self._create(arguments)
        if tool == "update_workflow":
            return self._update(arguments)
        if tool == "archive_workflow":
            return self._archive(arguments, payload.get("confirmation"))
        raise AssertionError(f"Unhandled allowed tool: {tool}")

    def _workflow_id(self, arguments: dict[str, Any]) -> str:
        workflow_id = bounded_string(
            arguments.get("workflowId"),
            "workflowId",
            required=True,
            maximum=128,
        )
        if not WORKFLOW_ID_RE.fullmatch(workflow_id):
            raise GatewayError(HTTPStatus.BAD_REQUEST, "workflowId is invalid")
        return workflow_id

    def _lookup(self, workflow_id: str) -> dict[str, Any]:
        search_response = self.client.call("search_workflows", {"limit": 200})
        if not search_response.get("ok"):
            raise GatewayError(
                HTTPStatus.BAD_GATEWAY,
                "n8n could not verify the workflow policy",
            )
        search_result = search_response.get("result", {})
        entries = (
            search_result.get("data", []) if isinstance(search_result, dict) else []
        )
        summary = next(
            (
                entry
                for entry in entries
                if isinstance(entry, dict) and str(entry.get("id") or "") == workflow_id
            ),
            None,
        )
        if not isinstance(summary, dict):
            raise GatewayError(HTTPStatus.NOT_FOUND, "Workflow was not found")
        if self.policy.is_protected(summary):
            raise GatewayError(
                HTTPStatus.FORBIDDEN,
                "That personal workflow is protected from the voice model",
            )

        response = self.client.call(
            "get_workflow_details",
            {"workflowId": workflow_id, "detailLevel": "full"},
        )
        if not response.get("ok"):
            if summary.get("availableInMCP") is False:
                raise GatewayError(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    "That non-personal workflow is not yet enabled for model editing",
                )
            raise GatewayError(HTTPStatus.BAD_GATEWAY, str(response.get("error")))
        workflow = response.get("result", {}).get("workflow")
        if not isinstance(workflow, dict):
            raise GatewayError(HTTPStatus.NOT_FOUND, "Workflow was not found")
        if self.policy.is_protected(workflow):
            raise GatewayError(
                HTTPStatus.FORBIDDEN,
                "That personal workflow is protected from the voice model",
            )
        return workflow

    def _search(self, arguments: dict[str, Any]) -> dict[str, Any]:
        clean: dict[str, Any] = {
            "limit": bounded_integer(
                arguments.get("limit", 20), "limit", minimum=1, maximum=50
            )
        }
        query = bounded_string(arguments.get("query", ""), "query", maximum=128)
        if query:
            clean["query"] = query
        response = self.client.call("search_workflows", clean)
        result = response.get("result", {})
        entries = result.get("data", []) if isinstance(result, dict) else []
        if not isinstance(entries, list):
            entries = []
        visible = [
            workflow
            for workflow in entries
            if isinstance(workflow, dict) and not self.policy.is_protected(workflow)
        ]
        return {
            "ok": bool(response.get("ok")),
            "result": {
                "data": visible,
                "count": len(visible),
                "protected_hidden": len(entries) - len(visible),
            },
        }

    def _details(self, arguments: dict[str, Any]) -> dict[str, Any]:
        workflow_id = self._workflow_id(arguments)
        workflow = self._lookup(workflow_id)
        return {
            "ok": True,
            "result": {
                "workflow": workflow,
                "policy": "visible and editable as an unpublished draft",
            },
        }

    def _reference(self, arguments: dict[str, Any]) -> dict[str, Any]:
        section = bounded_string(
            arguments.get("section", "patterns"), "section", maximum=32
        )
        allowed = {
            "patterns",
            "patterns_detailed",
            "expressions",
            "functions",
            "rules",
            "import",
            "guidelines",
            "design",
        }
        if section not in allowed:
            raise GatewayError(HTTPStatus.BAD_REQUEST, "Unsupported SDK section")
        return self.client.call("get_workflow_sdk_reference", {"section": section})

    def _search_nodes(self, arguments: dict[str, Any]) -> dict[str, Any]:
        queries = arguments.get("queries")
        if not isinstance(queries, list) or not queries:
            raise GatewayError(HTTPStatus.BAD_REQUEST, "queries must be a non-empty list")
        clean = [
            bounded_string(item, "query", required=True, maximum=80)
            for item in queries[:MAX_SEARCH_QUERIES]
        ]
        return self.client.call("search_nodes", {"queries": clean, "usage": "workflow"})

    def _node_types(self, arguments: dict[str, Any]) -> dict[str, Any]:
        node_ids = arguments.get("nodeIds")
        if not isinstance(node_ids, list) or not node_ids:
            raise GatewayError(HTTPStatus.BAD_REQUEST, "nodeIds must be a non-empty list")
        clean = []
        for item in node_ids[:8]:
            item = json_object(item, "nodeId entry")
            entry = {
                "nodeId": bounded_string(
                    item.get("nodeId"), "nodeId", required=True, maximum=128
                )
            }
            for key in ("version", "resource", "operation", "mode"):
                value = bounded_string(item.get(key, ""), key, maximum=64)
                if value:
                    entry[key] = value
            clean.append(entry)
        return self.client.call("get_node_types", {"nodeIds": clean})

    def _validate(self, arguments: dict[str, Any]) -> dict[str, Any]:
        code = bounded_string(
            arguments.get("code"),
            "code",
            required=True,
            maximum=MAX_CODE_LENGTH,
        )
        return self.client.call("validate_workflow", {"code": code})

    def _create(self, arguments: dict[str, Any]) -> dict[str, Any]:
        code = bounded_string(
            arguments.get("code"),
            "code",
            required=True,
            maximum=MAX_CODE_LENGTH,
        )
        name = bounded_string(arguments.get("name", ""), "name", maximum=128)
        if name:
            self.policy.reject_reserved_name(name)

        validation = self.client.call("validate_workflow", {"code": code})
        validation_result = validation.get("result", {})
        if not validation.get("ok") or validation_result.get("valid") is not True:
            return {
                "ok": False,
                "error": "Workflow code did not pass n8n validation",
                "result": {"validation": validation_result},
            }

        clean: dict[str, Any] = {"code": code}
        optional_limits = {
            "name": 128,
            "description": 255,
            "versionName": 80,
            "versionDescription": 1_000,
        }
        for key, maximum in optional_limits.items():
            value = bounded_string(arguments.get(key, ""), key, maximum=maximum)
            if value:
                clean[key] = value
        response = self.client.call("create_workflow_from_code", clean)
        result = response.get("result", {})
        workflow_id = result.get("workflowId") if isinstance(result, dict) else None
        if response.get("ok") and isinstance(workflow_id, str):
            tag_response = self.client.call(
                "update_workflow",
                {
                    "workflowId": workflow_id,
                    "operations": [{"type": "addTags", "names": ["casita-model"]}],
                    "versionName": "Marked as Casita model-managed",
                    "versionDescription": (
                        "This draft was created through the policy-enforced Casita gateway."
                    ),
                },
            )
            if not tag_response.get("ok"):
                result["policy_warning"] = "Created, but the model-management tag failed"
        if isinstance(result, dict):
            result["draft_only"] = True
            result["published"] = False
            result["credential_review_required"] = True
            result["credential_policy"] = (
                "Casita cannot inspect or select credentials; n8n may auto-bind a "
                "compatible credential to this inactive draft, so review it before publishing"
            )
        return response

    def _update(self, arguments: dict[str, Any]) -> dict[str, Any]:
        workflow_id = self._workflow_id(arguments)
        self._lookup(workflow_id)
        operations = arguments.get("operations")
        if not isinstance(operations, list) or not operations:
            raise GatewayError(HTTPStatus.BAD_REQUEST, "operations must be a non-empty list")
        if len(operations) > MAX_UPDATE_OPERATIONS:
            raise GatewayError(
                HTTPStatus.BAD_REQUEST,
                f"At most {MAX_UPDATE_OPERATIONS} update operations are allowed",
            )
        clean_operations = []
        for operation in operations:
            operation = json_object(operation, "operation")
            operation_type = bounded_string(
                operation.get("type"), "operation type", required=True, maximum=64
            )
            if operation_type == "setNodeCredential":
                raise GatewayError(
                    HTTPStatus.FORBIDDEN,
                    "The voice model cannot assign n8n credentials",
                )
            if operation_type == "addNode":
                node = operation.get("node")
                if isinstance(node, dict) and node.get("credentials"):
                    raise GatewayError(
                        HTTPStatus.FORBIDDEN,
                        "The voice model cannot add a node with credentials attached",
                    )
            if operation_type == "setWorkflowMetadata" and "name" in operation:
                self.policy.reject_reserved_name(operation.get("name"))
            clean_operations.append(operation)

        clean: dict[str, Any] = {
            "workflowId": workflow_id,
            "operations": clean_operations,
        }
        for key, maximum in (("versionName", 80), ("versionDescription", 1_000)):
            value = bounded_string(arguments.get(key, ""), key, maximum=maximum)
            if value:
                clean[key] = value
        response = self.client.call("update_workflow", clean)
        result = response.get("result")
        if isinstance(result, dict):
            result["draft_only"] = True
            result["published_version_changed"] = False
        return response

    def _archive(self, arguments: dict[str, Any], confirmation: Any) -> dict[str, Any]:
        workflow_id = self._workflow_id(arguments)
        workflow = self._lookup(workflow_id)
        name = str(workflow.get("name") or "")
        confirmation_text = bounded_string(
            confirmation, "confirmation", required=True, maximum=128
        )
        if not hmac.compare_digest(confirmation_text, name):
            raise GatewayError(
                HTTPStatus.CONFLICT,
                "Archive confirmation must exactly match the current workflow name",
            )
        response = self.client.call("archive_workflow", {"workflowId": workflow_id})
        result = response.get("result")
        if isinstance(result, dict):
            result["recoverable"] = True
            result["permanent_delete"] = False
        return response


def handler_for(gateway: WorkflowGateway) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "LoomModelWorkflows/1"

        def log_message(self, message: str, *args: Any) -> None:
            LOGGER.info("%s - %s", self.client_address[0], message % args)

        def _send(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status.value)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path != "/health":
                self._send(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            self._send(HTTPStatus.OK, gateway.health())

        def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
            if self.path != "/v1/call":
                self._send(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
            try:
                content_length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                content_length = 0
            if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
                self._send(
                    HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                    {"ok": False, "error": "invalid request size"},
                )
                return
            try:
                payload = json.loads(self.rfile.read(content_length))
                payload = json_object(payload, "request")
                result = gateway.handle(payload)
                self._send(HTTPStatus.OK, result)
            except json.JSONDecodeError:
                self._send(
                    HTTPStatus.BAD_REQUEST,
                    {"ok": False, "error": "request must contain valid JSON"},
                )
            except GatewayError as error:
                self._send(error.status, {"ok": False, "error": error.message})
            except Exception:
                LOGGER.exception("Unhandled workflow gateway failure")
                self._send(
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"ok": False, "error": "workflow gateway failed safely"},
                )

    return Handler


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=os.getenv("LOOM_MODEL_LISTEN_HOST", "127.0.0.1"))
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.getenv("LOOM_MODEL_LISTEN_PORT", "5681")),
    )
    parser.add_argument(
        "--mcp-url",
        default=os.getenv(
            "LOOM_MODEL_MCP_URL", "http://127.0.0.1:5678/mcp-server/http"
        ),
    )
    credentials_directory = Path(os.environ.get("CREDENTIALS_DIRECTORY", "/run/credentials"))
    parser.add_argument(
        "--token-file",
        type=Path,
        default=credentials_directory / "n8n_mcp_token",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=os.getenv("LOOM_MODEL_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    gateway = WorkflowGateway(
        McpClient(args.mcp_url, args.token_file),
        WorkflowPolicy.from_environment(),
    )
    server = ThreadingHTTPServer((args.host, args.port), handler_for(gateway))
    LOGGER.info("Loom model workflow gateway ready at %s:%s", args.host, args.port)
    server.serve_forever()


if __name__ == "__main__":
    main()

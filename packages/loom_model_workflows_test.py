"""Policy tests for the Loom model workflow gateway."""

from __future__ import annotations

from http import HTTPStatus
import unittest

from loom_model_workflows import GatewayError, WorkflowGateway, WorkflowPolicy


PERSONAL = {
    "id": "ThornNightBrainDump",
    "name": "Thorn | Night brain dump",
    "tags": [],
}
SYSTEM = {
    "id": "FleetHealth",
    "name": "ThornixOS | Fleet health",
    "availableInMCP": True,
    "tags": [{"name": "operations"}],
    "nodes": [
        {
            "name": "Notify",
            "credentials": {
                "httpBearerAuth": {"id": "secret-id", "name": "Private token"}
            },
        }
    ],
    "scopes": ["workflow:read", "workflow:publish"],
    "canExecute": True,
}
TAGGED_PERSONAL = {
    "id": "FuturePersonal",
    "name": "Private future workflow",
    "tags": [{"name": "Personal"}],
}


class FakeClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, dict]] = []
        self.workflows = {
            PERSONAL["id"]: PERSONAL,
            SYSTEM["id"]: SYSTEM,
            TAGGED_PERSONAL["id"]: TAGGED_PERSONAL,
        }

    def call(self, tool: str, arguments: dict) -> dict:
        self.calls.append((tool, arguments))
        if tool == "search_workflows":
            return {
                "ok": True,
                "result": {"data": list(self.workflows.values()), "count": 3},
            }
        if tool == "get_workflow_details":
            workflow = self.workflows.get(arguments["workflowId"])
            return {"ok": True, "result": {"workflow": workflow}}
        if tool == "validate_workflow":
            valid = arguments["code"] != "invalid"
            return {
                "ok": valid,
                "result": {"valid": valid, "errors": [] if valid else ["invalid"]},
            }
        if tool == "create_workflow_from_code":
            created = {
                "workflowId": "CasitaCreated",
                "name": arguments.get("name", "Created"),
                "autoAssignedCredentials": [
                    {
                        "nodeName": "Notify",
                        "credentialName": "Private token",
                        "credentialType": "httpBearerAuth",
                    }
                ],
                "targetProject": {
                    "id": "personal-project",
                    "name": "Jamie <private@example.invalid>",
                    "type": "personal",
                },
            }
            self.workflows[created["workflowId"]] = {
                "id": created["workflowId"],
                "name": created["name"],
                "tags": [],
            }
            return {"ok": True, "result": created}
        if tool == "update_workflow":
            return {
                "ok": True,
                "result": {
                    "workflowId": arguments["workflowId"],
                    "appliedOperations": len(arguments["operations"]),
                },
            }
        if tool == "archive_workflow":
            workflow = self.workflows[arguments["workflowId"]]
            return {
                "ok": True,
                "result": {
                    "archived": True,
                    "workflowId": workflow["id"],
                    "name": workflow["name"],
                },
            }
        return {"ok": True, "result": {}}


class WorkflowPolicyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.client = FakeClient()
        self.gateway = WorkflowGateway(self.client, WorkflowPolicy())

    def assert_forbidden(self, callable_) -> None:
        with self.assertRaises(GatewayError) as context:
            callable_()
        self.assertEqual(context.exception.status, HTTPStatus.FORBIDDEN)

    def test_search_hides_named_and_tagged_personal_workflows(self) -> None:
        result = self.gateway.handle(
            {"tool": "search_workflows", "arguments": {"limit": 20}}
        )
        self.assertEqual(
            [entry["id"] for entry in result["result"]["data"]],
            ["FleetHealth"],
        )
        self.assertEqual(result["result"]["protected_hidden"], 2)

    def test_search_rejects_non_numeric_limit(self) -> None:
        with self.assertRaises(GatewayError) as context:
            self.gateway.handle(
                {"tool": "search_workflows", "arguments": {"limit": "lots"}}
            )
        self.assertEqual(context.exception.status, HTTPStatus.BAD_REQUEST)

    def test_details_reject_protected_workflow(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "get_workflow_details",
                    "arguments": {"workflowId": PERSONAL["id"]},
                }
            )
        )
        self.assertEqual(
            self.client.calls, []
        )

    def test_details_strip_credential_and_scope_metadata(self) -> None:
        result = self.gateway.handle(
            {
                "tool": "get_workflow_details",
                "arguments": {"workflowId": SYSTEM["id"]},
            }
        )
        workflow = result["result"]["workflow"]
        self.assertNotIn("credentials", workflow["nodes"][0])
        self.assertNotIn("scopes", workflow)
        self.assertNotIn("canExecute", workflow)
        self.assertEqual(
            self.client.calls[0], ("search_workflows", {"limit": 50})
        )

    def test_update_rejects_protected_workflow_before_mutation(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "update_workflow",
                    "arguments": {
                        "workflowId": PERSONAL["id"],
                        "operations": [
                            {
                                "type": "setWorkflowMetadata",
                                "name": "Changed",
                            }
                        ],
                    },
                }
            )
        )
        self.assertFalse(any(tool == "update_workflow" for tool, _ in self.client.calls))

    def test_archive_rejects_protected_workflow_before_mutation(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "archive_workflow",
                    "arguments": {"workflowId": PERSONAL["id"]},
                    "confirmation": PERSONAL["name"],
                }
            )
        )
        self.assertFalse(any(tool == "archive_workflow" for tool, _ in self.client.calls))

    def test_create_validates_and_marks_draft(self) -> None:
        result = self.gateway.handle(
            {
                "tool": "create_workflow_from_code",
                "arguments": {
                    "name": "Casita | Test draft",
                    "code": "workflow('test', [])",
                    "versionName": "Initial draft",
                },
            }
        )
        self.assertTrue(result["ok"])
        self.assertTrue(result["result"]["draft_only"])
        self.assertFalse(result["result"]["published"])
        self.assertTrue(result["result"]["credential_review_required"])
        self.assertEqual(result["result"]["auto_bound_credential_count"], 1)
        self.assertNotIn("autoAssignedCredentials", result["result"])
        self.assertEqual(result["result"]["target_project"], "default n8n project")
        self.assertNotIn("targetProject", result["result"])
        self.assertEqual(
            [tool for tool, _ in self.client.calls],
            ["validate_workflow", "create_workflow_from_code", "update_workflow"],
        )

    def test_create_rejects_reserved_personal_name(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "create_workflow_from_code",
                    "arguments": {
                        "name": PERSONAL["name"],
                        "code": "workflow('test', [])",
                    },
                }
            )
        )

    def test_create_rejects_future_personal_namespace(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "create_workflow_from_code",
                    "arguments": {
                        "name": "Thorn | Future personal automation",
                        "code": "workflow('test', [])",
                    },
                }
            )
        )

    def test_update_rejects_credential_assignment(self) -> None:
        self.assert_forbidden(
            lambda: self.gateway.handle(
                {
                    "tool": "update_workflow",
                    "arguments": {
                        "workflowId": SYSTEM["id"],
                        "operations": [
                            {
                                "type": "setNodeCredential",
                                "nodeName": "Send",
                                "credentialKey": "httpHeaderAuth",
                                "credentialId": "secret",
                            }
                        ],
                    },
                }
            )
        )

    def test_archive_requires_exact_name_and_is_recoverable(self) -> None:
        with self.assertRaises(GatewayError) as context:
            self.gateway.handle(
                {
                    "tool": "archive_workflow",
                    "arguments": {"workflowId": SYSTEM["id"]},
                    "confirmation": "wrong name",
                }
            )
        self.assertEqual(context.exception.status, HTTPStatus.CONFLICT)

        result = self.gateway.handle(
            {
                "tool": "archive_workflow",
                "arguments": {"workflowId": SYSTEM["id"]},
                "confirmation": SYSTEM["name"],
            }
        )
        self.assertTrue(result["result"]["archived"])
        self.assertTrue(result["result"]["recoverable"])
        self.assertFalse(result["result"]["permanent_delete"])

    def test_publish_and_execute_are_never_available(self) -> None:
        for tool in ("publish_workflow", "execute_workflow", "unpublish_workflow"):
            self.assert_forbidden(
                lambda tool=tool: self.gateway.handle(
                    {"tool": tool, "arguments": {}}
                )
            )


if __name__ == "__main__":
    unittest.main()

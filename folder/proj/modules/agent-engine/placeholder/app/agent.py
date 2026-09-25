"""Bootstrap placeholder agent.

Vertex AI Agent Engine requires a source archive at create time. This trivial object
satisfies that requirement so Terraform can create the engine "shell". The agents repo
(via agents-cli / the SDK) deploys the real orchestrator + specialists afterwards, and
the Terraform lifecycle ignore_changes keeps this placeholder from ever reverting it.
"""


class PlaceholderAgent:
    def query(self, *args, **kwargs):
        return {"status": "placeholder - deploy the real agent from the agents repo"}


agent = PlaceholderAgent()

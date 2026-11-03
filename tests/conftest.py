import os

# Fuera de EC2 no hay servicio de metadatos: se usan valores locales.
os.environ.setdefault("INSTANCE_METADATA_DISABLED", "1")

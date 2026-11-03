"""Convierte reportes JUnit de pytest en una tabla Markdown para el resumen
del job de GitHub Actions ($GITHUB_STEP_SUMMARY)."""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main(paths: list[str]) -> None:
    print("## Resultado de las pruebas\n")
    print("| Suite | Total | Exitosas | Fallidas | Errores | Omitidas | Tiempo (s) |")
    print("|-------|------:|---------:|---------:|--------:|---------:|-----------:|")
    failed_cases = []
    for path in paths:
        if not Path(path).exists():
            print(f"| {Path(path).stem} | - | - | - | - | - | no se ejecuto |")
            continue
        root = ET.parse(path).getroot()
        suite = root if root.tag == "testsuite" else root.find("testsuite")
        total = int(suite.get("tests", 0))
        failures = int(suite.get("failures", 0))
        errors = int(suite.get("errors", 0))
        skipped = int(suite.get("skipped", 0))
        passed = total - failures - errors - skipped
        elapsed = float(suite.get("time", 0))
        icon = "✅" if failures == errors == 0 else "❌"
        print(
            f"| {icon} {Path(path).stem} | {total} | {passed} | {failures} | {errors} "
            f"| {skipped} | {elapsed:.2f} |"
        )
        for case in suite.iter("testcase"):
            if case.find("failure") is not None or case.find("error") is not None:
                failed_cases.append(f"{case.get('classname')}::{case.get('name')}")
    if failed_cases:
        print("\n### Pruebas fallidas\n")
        for name in failed_cases:
            print(f"- `{name}`")


if __name__ == "__main__":
    main(sys.argv[1:])

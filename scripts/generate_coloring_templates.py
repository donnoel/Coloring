#!/usr/bin/env python3
"""Generate built-in coloring templates using OpenAI Images API."""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass


API_URL = "https://api.openai.com/v1/images/generations"
MODEL = "gpt-image-1"
SIZE = "1536x1024"
OUTPUT_FORMAT = "png"

STYLE_SUFFIX = (
    "Coloring book line art, landscape orientation, complete scene, "
    "bold black outlines only, clean closed shapes, white background, "
    "no grayscale, no shading, no hatching, no text, no letters, "
    "no logo, kid-friendly."
)


@dataclass(frozen=True)
class TemplateSpec:
    category: str
    title: str
    subject_prompt: str
    file_name: str | None = None


TEMPLATE_SPECS: list[TemplateSpec] = [
    TemplateSpec("Scenery", "Sunrise Mountain Valley", "birds flying above a mountain valley with pine trees and river"),
    TemplateSpec("Scenery", "Lakeside Cabin Picnic", "a wooden cabin by a calm lake with picnic table, hills, and clouds"),
    TemplateSpec("Scenery", "Waterfall Jungle Path", "a jungle path leading to a tall waterfall with tropical plants"),
    TemplateSpec("Scenery", "Winter Village Park", "a snowy village park with benches, lamp posts, and cozy houses"),
    TemplateSpec("Scenery", "Desert Canyon Road", "a winding road through desert canyon with cacti and rock arches"),
    TemplateSpec("Scenery", "Island Beach Day", "a beach scene with palm trees, umbrellas, sand castle, and gentle waves"),
    TemplateSpec("Scenery", "Forest Camping Night", "a forest campsite with tent, campfire ring, pine trees, and moon"),
    TemplateSpec("Scenery", "Countryside Windmill Farm", "rolling farm fields with windmill, barn, and grazing sheep"),
    TemplateSpec("Scenery", "Rainy City Garden", "a city garden with fountain, flower beds, and umbrellas under rain clouds"),
    TemplateSpec("Scenery", "Hot Air Balloon Meadow", "hot air balloons over a flower meadow and distant mountains"),
    TemplateSpec("Racing", "Formula Track Sprint", "two formula race cars speeding on a professional track with grandstands"),
    TemplateSpec("Racing", "Rally Dirt Drift", "rally cars drifting on a dirt mountain road with spectators"),
    TemplateSpec("Racing", "Motorcycle Speedway", "motorcycles racing around an oval speedway with flags"),
    TemplateSpec("Racing", "Go Kart Championship", "go karts racing through tight turns on an outdoor circuit"),
    TemplateSpec("Fun", "Carnival Day", "carnival scene with ferris wheel, carousel, and game booths", "15-racing.png"),
    TemplateSpec("Fun", "City Skate Park", "kids riding skateboards and scooters in a skate park", "16-racing.png"),
    TemplateSpec("Fun", "Music Band Stage", "family music band playing on outdoor stage with audience", "17-racing.png"),
    TemplateSpec("Fun", "Space Classroom", "classroom inside a spaceship with planets through windows", "18-racing.png"),
    TemplateSpec("Fun", "Construction Zone", "construction site with cranes, bulldozer, and workers", "19-racing.png"),
    TemplateSpec("Fun", "Bakery Street", "street of bakeries with cakes, bread stands, and customers", "20-racing.png"),
    TemplateSpec("Animals", "Savanna Waterhole", "elephants, zebras, and giraffes around a savanna waterhole"),
    TemplateSpec("Animals", "Arctic Friends", "polar bears, seals, and penguins on icebergs by the sea"),
    TemplateSpec("Animals", "Rainforest Canopy", "parrots, monkeys, and toucans in a dense rainforest canopy"),
    TemplateSpec("Animals", "Farm Morning", "farmyard with cows, chickens, pigs, barn, and tractor"),
    TemplateSpec("Animals", "Ocean Reef Parade", "sea turtle, fish, coral reef, and starfish underwater scene"),
    TemplateSpec("Animals", "Dog Park Adventure", "dogs playing in a park with trees, benches, and fountain"),
    TemplateSpec("Animals", "Horse Ranch Trail", "horses running near a ranch fence with hills and clouds"),
    TemplateSpec("Animals", "Butterfly Garden", "butterflies over a flower garden with gazebo and pathways"),
    TemplateSpec("Animals", "Woodland Picnic", "fox, rabbit, and deer near a picnic blanket in forest clearing"),
    TemplateSpec("Animals", "Panda Bamboo Forest", "pandas in a bamboo forest with stream and rocks"),
    TemplateSpec("Fantasy", "Dragon Castle Flight", "friendly dragon flying around a hilltop castle and banners"),
    TemplateSpec("Fantasy", "Mermaid Lagoon", "mermaids, seashell palace, and dolphins in an ocean lagoon"),
    TemplateSpec("Fantasy", "Wizard Tower Garden", "wizard tower with magic garden, books, and glowing stars"),
    TemplateSpec("Fantasy", "Unicorn Rainbow Field", "unicorns in a meadow with rainbow and whimsical trees"),
    TemplateSpec("Fantasy", "Sky Pirate Airships", "airships racing through clouds near floating islands"),
    TemplateSpec("Fantasy", "Robot City Parade", "friendly robots in a futuristic city festival"),
    TemplateSpec("Fantasy", "Treasure Map Quest", "adventurers on a jungle island following a treasure map"),
    TemplateSpec("Fantasy", "Knight Tournament", "knights on horses in a castle tournament field"),
    TemplateSpec("Fantasy", "Candy Village", "candy-themed village with gingerbread houses and candy trees"),
    TemplateSpec("Fantasy", "Moon Base Discovery", "astronaut kids exploring a moon base with rover"),
    TemplateSpec("Fun", "Carnival Day", "carnival scene with ferris wheel, carousel, and game booths"),
    TemplateSpec("Fun", "City Skate Park", "kids riding skateboards and scooters in a skate park"),
    TemplateSpec("Fun", "Music Band Stage", "family music band playing on outdoor stage with audience"),
    TemplateSpec("Fun", "Space Classroom", "classroom inside a spaceship with planets through windows"),
    TemplateSpec("Fun", "Construction Zone", "construction site with cranes, bulldozer, and workers"),
    TemplateSpec("Fun", "Bakery Street", "street of bakeries with cakes, bread stands, and customers"),
    TemplateSpec("Fun", "Sports Field Mix", "kids playing soccer, baseball, and frisbee in a large park"),
    TemplateSpec("Fun", "Museum Adventure", "family exploring dinosaur museum exhibits and fossils"),
    TemplateSpec("Fun", "Harbor Market", "busy harbor with fishing boats, market stalls, and seagulls"),
    TemplateSpec("Fun", "Robot Pet Shop", "pet shop with robot pets, accessories, and happy kids"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default="Coloring/Resources/Templates/BuiltIn",
        help="Directory where PNG templates are written.",
    )
    parser.add_argument(
        "--manifest",
        default="Coloring/Resources/Templates/template_manifest.json",
        help="Path to JSON manifest file.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate files even if they already exist.",
    )
    parser.add_argument(
        "--sleep",
        type=float,
        default=0.4,
        help="Delay between API calls in seconds.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Generate only the first N templates (default: 20).",
    )
    return parser.parse_args()


def category_slug(name: str) -> str:
    return name.lower().replace(" ", "-")


def build_filename(index: int, spec: TemplateSpec) -> str:
    if spec.file_name:
        return spec.file_name

    return f"{index + 1:02d}-{category_slug(spec.category)}.png"


def build_prompt(subject_prompt: str) -> str:
    return f"{subject_prompt}. {STYLE_SUFFIX}"


def api_generate_image_b64(api_key: str, prompt: str) -> str:
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "size": SIZE,
        "output_format": OUTPUT_FORMAT,
    }

    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            raw_response = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code}: {body}") from error

    payload = json.loads(raw_response)
    data = payload.get("data")
    if not data:
        raise RuntimeError(f"Missing image data: {raw_response}")

    b64 = data[0].get("b64_json")
    if not b64:
        raise RuntimeError(f"Missing b64_json: {raw_response}")

    return b64


def main() -> int:
    args = parse_args()
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("error: OPENAI_API_KEY is not set", file=sys.stderr)
        return 1

    out_dir = pathlib.Path(args.out_dir)
    manifest_path = pathlib.Path(args.manifest)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    selected_specs = TEMPLATE_SPECS[: max(0, args.limit)]

    manifest_entries: list[dict[str, str]] = []

    for index, spec in enumerate(selected_specs):
        filename = build_filename(index, spec)
        output_path = out_dir / filename

        manifest_entries.append(
            {
                "fileName": filename,
                "title": spec.title,
                "category": spec.category,
            }
        )

        if output_path.exists() and not args.force:
            print(f"[{index + 1:02d}/{len(selected_specs)}] skip {filename}")
            continue

        prompt = build_prompt(spec.subject_prompt)
        print(f"[{index + 1:02d}/{len(selected_specs)}] generate {filename} - {spec.title}")
        b64_image = api_generate_image_b64(api_key=api_key, prompt=prompt)
        output_path.write_bytes(base64.b64decode(b64_image))

        if index < len(selected_specs) - 1:
            time.sleep(max(0, args.sleep))

    manifest_path.write_text(json.dumps(manifest_entries, indent=2) + "\n", encoding="utf-8")
    print(f"wrote manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

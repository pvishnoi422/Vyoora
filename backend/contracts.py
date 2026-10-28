"""Validate model output before it can become a successful product result."""
from safety import ServiceError


def validate_model_result(data):
    if not isinstance(data, dict):
        raise ValueError("Expected analysis object")
    ingredients = data.get("ingredients")
    all_ingredients = data.get("all_ingredients", ingredients)
    if not isinstance(ingredients, list) or not isinstance(all_ingredients, list):
        raise ValueError("Missing ingredient lists")
    if not ingredients or not all_ingredients:
        raise ServiceError("no_ingredients", "We couldn't read an ingredient list. Try a clearer photo.", 422)
    if len(ingredients) > 200 or len(all_ingredients) > 200:
        raise ValueError("Too many ingredients")
    for item in ingredients + all_ingredients:
        if not isinstance(item, str) or not item.strip() or len(item) > 200:
            raise ValueError("Invalid ingredient")
    summary = data.get("summary")
    if not isinstance(summary, str) or not summary.strip() or len(summary) > 5000:
        raise ValueError("Missing summary")
    concerns = data.get("concerns")
    if not isinstance(concerns, list) or len(concerns) > 200:
        raise ValueError("Missing concerns")
    for concern in concerns:
        if not isinstance(concern, dict):
            raise ValueError("Invalid concern")
        for key in ("ingredient", "reason"):
            if not isinstance(concern.get(key), str) or not concern[key].strip():
                raise ValueError("Incomplete concern")
        references = concern.get("references", [])
        if not isinstance(references, list) or any(not isinstance(r, str) for r in references):
            raise ValueError("Invalid references")
        for field in ("category", "eu_note"):
            if field in concern and not isinstance(concern[field], str):
                raise ValueError("Invalid concern text")
        for field in ("eu_restricted", "eu_banned"):
            if field in concern and type(concern[field]) is not bool:
                raise ValueError("Invalid concern flag")
        if "ingredient_position" in concern and (type(concern["ingredient_position"]) is not int or not 1 <= concern["ingredient_position"] <= 200):
            raise ValueError("Invalid ingredient position")
    for field in ("brand", "product_name", "product_type", "product_type_detail", "formula_type", "score_label"):
        if field in data and not isinstance(data[field], str):
            raise ValueError("Invalid text field")
    for field in ("score_rationale", "skin_compatibility"):
        if field in data and not isinstance(data[field], dict):
            raise ValueError("Invalid object field")
    for obj, fields in [(data.get("score_rationale", {}), ("positives", "negatives")),
                        (data.get("skin_compatibility", {}), ("best_for", "use_caution", "less_ideal_for")),
                        (data, ("who_should_avoid",))]:
        for field in fields:
            values = obj.get(field, [])
            if not isinstance(values, list) or any(not isinstance(v, str) for v in values):
                raise ValueError("Invalid advice list")
    confidence = data.get("score_rationale", {}).get("evidence_confidence", "")
    if not isinstance(confidence, str):
        raise ValueError("Invalid evidence confidence")
    return data

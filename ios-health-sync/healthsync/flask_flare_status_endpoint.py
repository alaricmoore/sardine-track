"""
Flask API Endpoint for Flare Status
Add this to your app.py file (before the health-sync route or at the end of API routes)
"""

@app.route("/api/flare-status")
@csrf.exempt
def api_flare_status():
    """JSON flare status for iOS companion app."""
    # --- Auth (same pattern as health-sync) ---
    token = CONFIG.get("api_token")
    if not token:
        return jsonify({"error": "api_token not configured"}), 500
    
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or auth[7:] != token:
        return jsonify({"error": "unauthorized"}), 401
    
    user_id = request.args.get("user_id")
    if not user_id:
        return jsonify({"error": "user_id required"}), 400
    
    try:
        user_id = int(user_id)
    except ValueError:
        return jsonify({"error": "invalid user_id"}), 400
    
    # Get today's date
    today = datetime.now().date()
    today_str = today.isoformat()
    
    # Fetch today's health data entry (or most recent)
    entry = HealthData.query.filter_by(user_id=user_id, date=today).first()
    if not entry:
        # Try yesterday if today doesn't exist yet
        yesterday = today - timedelta(days=1)
        entry = HealthData.query.filter_by(user_id=user_id, date=yesterday).first()
        if not entry:
            return jsonify({
                "ok": False,
                "reason": "insufficient_data",
                "date": today_str
            })
    
    # --- Reuse forecast scoring logic ---
    # (This assumes you have a compute_flare_score function similar to the /forecast route)
    # You'll need to adapt this to match your actual scoring implementation
    
    try:
        score_result = compute_flare_score(entry)  # Your existing scoring function
        
        # Get yesterday's score for delta calculation
        yesterday = today - timedelta(days=1)
        yesterday_entry = HealthData.query.filter_by(user_id=user_id, date=yesterday).first()
        
        score_delta = None
        delta_direction = None
        if yesterday_entry:
            yesterday_score = compute_flare_score(yesterday_entry).get("score", 0)
            score_delta = score_result["score"] - yesterday_score
            delta_direction = "up" if score_delta > 0 else "down" if score_delta < 0 else "stable"
        
        # Get doses due today (from existing dose schedule/taper system)
        doses_due = []
        # This assumes you have a Dose or MedSchedule model
        # Adapt to your actual database schema:
        # Example:
        # from models import DoseSchedule  # or whatever your model is
        # scheduled_doses = DoseSchedule.query.filter_by(
        #     user_id=user_id,
        #     date=today,
        #     taken=False
        # ).all()
        # for dose in scheduled_doses:
        #     doses_due.append({
        #         "id": dose.id,
        #         "drug_name": dose.drug_name,
        #         "dose_label": dose.dose_label,
        #         "scheduled_time": dose.scheduled_time.strftime("%H:%M"),
        #         "taken": dose.taken
        #     })
        
        return jsonify({
            "ok": True,
            "date": today_str,
            "score": score_result["score"],
            "weighted_score": score_result.get("weighted_score", score_result["score"]),
            "max_score": score_result["max_score"],
            "threshold": score_result.get("threshold", 8.0),
            "predicted_flare": score_result["predicted_flare"],
            "risk_level": score_result["risk_level"],
            "risk_color": score_result["risk_color"],
            "score_delta": score_delta,
            "delta_direction": delta_direction,
            "factors": score_result.get("factors", []),
            "doses_due": doses_due
        })
    
    except Exception as e:
        app.logger.error(f"Error computing flare status: {e}")
        return jsonify({
            "ok": False,
            "reason": "scoring_error",
            "error": str(e)
        }), 500


def compute_flare_score(entry):
    """
    Compute flare risk score from a HealthData entry.
    This is a placeholder — adapt to your actual scoring logic from /forecast.
    
    Should return a dict with:
    {
        "score": float,
        "max_score": float,
        "predicted_flare": bool,
        "risk_level": str,  # "low", "moderate", "high"
        "risk_color": str,  # hex color
        "factors": [{"name": str, "points": float, "color": str}, ...]
    }
    """
    # TODO: Implement your actual scoring logic here
    # This is just a stub to show the structure
    
    score = 0.0
    factors = []
    max_score = 20.0  # Adjust to your actual max
    
    # Example factor calculations (adapt to your real logic):
    if entry.sun_exposure_min and entry.sun_exposure_min > 120:
        uv_points = min(3.0, (entry.sun_exposure_min - 120) / 60)
        score += uv_points
        factors.append({
            "name": "UV Exposure",
            "points": uv_points,
            "color": "#d4b84a"
        })
    
    # Add more factor calculations based on your criteria...
    
    predicted_flare = score >= 8.0  # Your threshold
    
    if score < 4:
        risk_level = "low"
        risk_color = "#4a9d5f"
    elif score < 8:
        risk_level = "moderate"
        risk_color = "#d4a054"
    else:
        risk_level = "high"
        risk_color = "#c44e58"
    
    return {
        "score": round(score, 1),
        "max_score": max_score,
        "predicted_flare": predicted_flare,
        "risk_level": risk_level,
        "risk_color": risk_color,
        "factors": factors
    }

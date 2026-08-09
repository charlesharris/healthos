# frozen_string_literal: true

module Hypertension
  # Review priority policy (HO §43, S2C-011, S2C-012).
  #
  # ⚠️ NON-CLINICAL fixtures (HO §175).
  #
  # S2C-011 is the load-bearing rule here: **priority is operational policy,
  # not statistical evidence.** A STRONG Difference does not make a Case
  # urgent, and a WEAK one does not make it ignorable — urgency is about how
  # soon a human should look, which depends on the kind of work and how long
  # it has waited, not on how confident the statistics are.
  #
  # So this policy deliberately does NOT read evidence_level. Coupling them
  # would collapse two independent axes into one and reproduce exactly the
  # "AI Risk Score: 87" that HO §43 and CLAUDE.md forbid.
  #
  # Every decision records its reason (S2C-012): no Case ever carries an
  # unexplained ranking.
  module PriorityPolicy
    Result = Struct.new(:priority, :reasons, keyword_init: true)

    module_function

    def call(case_record:, as_of: Time.current)
      reasons = []

      # Instrumentation problems are time-sensitive in a way biology often is
      # not: every day a broken feed continues, more evidence is lost and
      # cannot be recovered.
      if case_record.case_type == "monitoring_interruption"
        reasons << reason("monitoring_interrupted", "Data collection has stopped; evidence is being lost")
        return Result.new(priority: "today", reasons: reasons)
      end

      # STAT-036: "we do not know yet" is a successful output, and watching is
      # the right operational response — not escalation and not closure.
      #
      # Checked BEFORE age, deliberately. A Case that is legitimately being
      # watched for more data will age by design; escalating it for that would
      # punish the honest answer and push operators toward closing Cases to
      # keep the queue quiet.
      if case_record.analysis_status == "insufficient_evidence"
        reasons << reason("insufficient_evidence", "Not enough evidence yet; awaiting more data")
        return Result.new(priority: "watch", reasons: reasons)
      end

      age_days = ((as_of - case_record.detected_at) / 1.day).floor

      # "Aged UNREVIEWED", and it now actually checks that. The first version
      # only checked age, so a Case someone had already looked at and parked
      # would be escalated for the crime of still existing — the rule's name
      # promised something the code did not do.
      if age_days >= 14 && case_record.last_reviewed_at.nil?
        reasons << reason("aged_unreviewed", "Open and never reviewed for #{age_days} days")
        return Result.new(priority: "today", reasons: reasons)
      end

      reasons << reason("default_routine", "No policy rule elevated this Case")
      Result.new(priority: "routine", reasons: reasons)
    end

    def reason(code, explanation)
      { "code" => code, "explanation" => explanation, "source" => "hypertension.priority_policy.v1" }
    end
  end
end

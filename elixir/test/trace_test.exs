defmodule TTM.TraceTest do
  use ExUnit.Case, async: false

  defmodule CapturingStore do
    @moduledoc false

    @agent __MODULE__.Agent

    def append(record) do
      ensure_started()
      Agent.update(@agent, fn state -> %{state | records: [record | state.records]} end)
      :ok
    end

    def stream(opts) do
      ensure_started()

      Agent.get_and_update(@agent, fn state ->
        {Enum.reverse(state.records), %{state | last_stream_opts: opts}}
      end)
      |> Stream.map(& &1)
    end

    def last_stream_opts do
      ensure_started()
      Agent.get(@agent, fn state -> state.last_stream_opts end)
    end

    def reset! do
      ensure_started()
      Agent.update(@agent, fn _ -> initial_state() end)
      :ok
    end

    defp ensure_started do
      case Process.whereis(@agent) do
        nil -> Agent.start_link(fn -> initial_state() end, name: @agent)
        _ -> :ok
      end

      :ok
    end

    defp initial_state do
      %{records: [], last_stream_opts: nil}
    end
  end

  defmodule CapturingIntegrity do
    @moduledoc false

    @agent __MODULE__.Agent

    def verify(seal, record) do
      ensure_started()
      Agent.update(@agent, fn _ -> {seal, record} end)
      :ok
    end

    def last_call do
      ensure_started()
      Agent.get(@agent, & &1)
    end

    def reset! do
      ensure_started()
      Agent.update(@agent, fn _ -> nil end)
      :ok
    end

    defp ensure_started do
      case Process.whereis(@agent) do
        nil -> Agent.start_link(fn -> nil end, name: @agent)
        _ -> :ok
      end

      :ok
    end
  end

  defmodule VerifyBridge do
    @moduledoc false

    def verify("valid-seal", _record), do: :ok
    def verify(_seal, _record), do: {:error, :invalid_seal}
  end

  defmodule EnvelopeIntegrity do
    @moduledoc false

    @agent __MODULE__.Agent

    def verify(seal, record) do
      ensure_started()
      Agent.update(@agent, &[{seal, record} | &1])

      case seal do
        "valid-seal" -> :ok
        "missing-verifier-seal" -> {:error, :verify_not_configured}
        _ -> {:error, :invalid_seal}
      end
    end

    def calls do
      ensure_started()
      Agent.get(@agent, &Enum.reverse/1)
    end

    def reset! do
      ensure_started()
      Agent.update(@agent, fn _ -> [] end)
      :ok
    end

    defp ensure_started do
      case Process.whereis(@agent) do
        nil -> Agent.start_link(fn -> [] end, name: @agent)
        _ -> :ok
      end

      :ok
    end
  end

  setup do
    Application.put_env(:ttm, :allow_trace_reset, true)
    Application.put_env(:ttm, :trace_store, TTM.Trace.InMemoryStore)
    Application.put_env(:ttm, :trace_integrity, TTM.Trace.NoopIntegrity)
    :ok = TTM.Trace.reset!()

    on_exit(fn ->
      Application.delete_env(:ttm, :allow_trace_reset)
      Application.delete_env(:ttm, :trace_store)
      Application.delete_env(:ttm, :trace_integrity)
      Application.delete_env(:ttm, :trace_dets_path)
      Application.delete_env(:ttm, :trace_verify_mfa)
      File.rm(dets_path())
    end)

    :ok
  end

  test "append adds records and stream preserves append order" do
    first = record("t-1", "s1", "s2")
    second = record("t-2", "s2", "s3")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)

    assert Enum.to_list(TTM.Trace.stream()) == [first, second]
  end

  test "stream order stays stable for longer append sequences" do
    records =
      1..50
      |> Enum.map(fn idx ->
        record("seq-#{idx}", "s#{idx}", "s#{idx + 1}")
      end)

    Enum.each(records, fn rec ->
      assert :ok = TTM.Trace.append(rec)
    end)

    assert Enum.to_list(TTM.Trace.stream()) == records
  end

  test "stream filters by thread_id" do
    first = record("t-1", "s1", "s2")
    second = record("t-2", "s2", "s3") |> Map.put(:thread_id, "thread-2")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)

    assert Enum.to_list(TTM.Trace.stream(thread_id: "thread-2")) == [second]
  end

  test "stream filters by lane" do
    main = record("t-1", "s1", "s2")
    shadow = record("t-2", "s2", "s3", lane: "shadow")

    assert :ok = TTM.Trace.append(main)
    assert :ok = TTM.Trace.append(shadow)

    assert Enum.to_list(TTM.Trace.stream(lane: "shadow")) == [shadow]
  end

  test "stream applies limit after filtering in append order" do
    first = record("t-1", "s1", "s2", lane: "main")
    second = record("t-2", "s2", "s3", lane: "shadow")
    third = record("t-3", "s3", "s4", lane: "main")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)
    assert :ok = TTM.Trace.append(third)

    assert Enum.to_list(TTM.Trace.stream(lane: "main", limit: 1)) == [first]
  end

  test "stream rejects unknown query keys" do
    assert_raise ArgumentError, ~r/unknown stream options/, fn ->
      TTM.Trace.stream(unknown_key: true) |> Enum.to_list()
    end
  end

  test "stream rejects invalid limit" do
    assert_raise ArgumentError, ~r/invalid :limit option/, fn ->
      TTM.Trace.stream(limit: -1) |> Enum.to_list()
    end
  end

  test "stream rejects non-keyword lists" do
    assert_raise ArgumentError, ~r/keyword list/, fn ->
      TTM.Trace.stream([:bad]) |> Enum.to_list()
    end
  end

  test "stream accepts forward-compatible no-op query fields" do
    record = record("t-1", "s1", "s2")

    assert :ok = TTM.Trace.append(record)

    assert Enum.to_list(
             TTM.Trace.stream(
               from_ts: "2026-04-23T00:00:00Z",
               to_ts: "2026-04-24T00:00:00Z",
               cursor: "opaque-cursor",
               verified: :unknown
             )
           ) == [record]
  end

  test "stream rejects invalid verified status" do
    assert_raise ArgumentError, ~r/invalid :verified option/, fn ->
      TTM.Trace.stream(verified: :trusted_by_vibes) |> Enum.to_list()
    end
  end

  test "stream passes valid query opts to configured store" do
    Application.put_env(:ttm, :trace_store, CapturingStore)
    CapturingStore.reset!()

    assert :ok = TTM.Trace.append(record("t-1", "s1", "s2"))
    assert Enum.to_list(TTM.Trace.stream(thread_id: "thread-1", lane: "main", limit: 10)) != []

    assert CapturingStore.last_stream_opts() == [thread_id: "thread-1", lane: "main", limit: 10]
  end

  test "append validates required fields" do
    assert {:error, {:validation, {:missing_fields, missing}}} =
             TTM.Trace.append(%{thread_id: "thread-1", transition_id: "t-1"})

    assert :ts in missing
    assert :seal in missing
  end

  test "append validates confidence in range 0..1" do
    assert {:error, {:validation, {:invalid_confidence, 1.5}}} =
             TTM.Trace.append(record("t-1", "s1", "s2", confidence: 1.5))
  end

  test "append validates required string fields are non-empty binaries" do
    invalid = record("t-1", "s1", "s2", lane: " ")

    assert {:error, {:validation, {:invalid_string_fields, invalid_fields}}} =
             TTM.Trace.append(invalid)

    assert :lane in invalid_fields
  end

  test "append rejects duplicate transition identity within a thread" do
    first = record("t-1", "s1", "s2")
    duplicate = record("t-1", "s2", "s3")

    assert :ok = TTM.Trace.append(first)

    assert {:error, {:duplicate_transition, {"thread-1", "t-1"}}} =
             TTM.Trace.append(duplicate)
  end

  test "concurrent append keeps transition identity unique" do
    record = record("parallel-1", "s1", "s2")

    results =
      1..2
      |> Enum.map(fn _ -> Task.async(fn -> TTM.Trace.append(record) end) end)
      |> Enum.map(&Task.await/1)
      |> Enum.sort()

    assert results == [:ok, {:error, {:duplicate_transition, {"thread-1", "parallel-1"}}}]
  end

  test "same transition_id is allowed for different threads" do
    first = record("t-1", "s1", "s2")

    second =
      record("t-1", "s2", "s3")
      |> Map.put(:thread_id, "thread-2")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)
  end

  test "trace delegates to configured store" do
    Application.put_env(:ttm, :trace_store, CapturingStore)
    CapturingStore.reset!()

    entry = record("t-custom", "x", "y")

    assert :ok = TTM.Trace.append(entry)
    assert Enum.to_list(TTM.Trace.stream()) == [entry]
  end

  test "dets store persists appended records on disk" do
    dets_path = dets_path()
    File.rm(dets_path)

    Application.put_env(:ttm, :trace_store, TTM.Trace.DetsStore)
    Application.put_env(:ttm, :trace_dets_path, dets_path)

    assert :ok = TTM.Trace.reset!()

    first = record("dets-1", "a", "b")
    second = record("dets-2", "b", "c")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)

    assert Enum.to_list(TTM.Trace.stream()) == [first, second]
  end

  test "dets store rejects duplicate transition identity" do
    dets_path = dets_path()
    File.rm(dets_path)

    Application.put_env(:ttm, :trace_store, TTM.Trace.DetsStore)
    Application.put_env(:ttm, :trace_dets_path, dets_path)

    assert :ok = TTM.Trace.reset!()
    first = record("dets-dup", "a", "b")
    duplicate = record("dets-dup", "b", "c")

    assert :ok = TTM.Trace.append(first)

    assert {:error, {:duplicate_transition, {"thread-1", "dets-dup"}}} =
             TTM.Trace.append(duplicate)
  end

  test "dets store stream supports thread_id, lane and limit filters" do
    dets_path = dets_path()
    File.rm(dets_path)

    Application.put_env(:ttm, :trace_store, TTM.Trace.DetsStore)
    Application.put_env(:ttm, :trace_dets_path, dets_path)

    assert :ok = TTM.Trace.reset!()

    first = record("dets-1", "a", "b")
    second = record("dets-2", "b", "c", lane: "shadow")
    third = record("dets-3", "c", "d") |> Map.put(:thread_id, "thread-2")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)
    assert :ok = TTM.Trace.append(third)

    assert Enum.to_list(TTM.Trace.stream(thread_id: "thread-1", lane: "main", limit: 1)) == [
             first
           ]
  end

  test "verify uses default integrity adapter" do
    assert {:error, :not_implemented} =
             TTM.Trace.verify("some-seal", record("t-1", "s1", "s2"))
  end

  test "verify delegates to configured integrity adapter" do
    Application.put_env(:ttm, :trace_integrity, CapturingIntegrity)
    CapturingIntegrity.reset!()

    record = record("t-1", "s1", "s2")

    assert :ok = TTM.Trace.verify("some-seal", record)
    assert CapturingIntegrity.last_call() == {"some-seal", record}
  end

  test "stream_envelopes returns record envelopes" do
    one = record("env-1", "s1", "s2")
    two = record("env-2", "s2", "s3")

    assert :ok = TTM.Trace.append(one)
    assert :ok = TTM.Trace.append(two)

    assert Enum.to_list(TTM.Trace.stream_envelopes()) == [
             %{record: one, verification_status: :unverified, verification_error: nil},
             %{record: two, verification_status: :unverified, verification_error: nil}
           ]
  end

  test "stream_envelopes without verified filter does not mutate records" do
    record = record("env-mutation", "s1", "s2")

    assert :ok = TTM.Trace.append(record)

    [%{record: envelope_record}] = Enum.to_list(TTM.Trace.stream_envelopes())

    assert envelope_record == record
    refute Map.has_key?(envelope_record, :verification_status)
    refute Map.has_key?(envelope_record, :verification_error)
  end

  test "stream_envelopes marks records as unverified when verification is not requested" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    assert :ok = TTM.Trace.append(record("env-unverified", "s1", "s2"))

    [%{verification_status: status}] = Enum.to_list(TTM.Trace.stream_envelopes())

    assert status == :unverified
    assert EnvelopeIntegrity.calls() == []
  end

  test "stream_envelopes can explicitly request unverified envelopes without verifier call" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    record = record("env-explicit-unverified", "s1", "s2", seal: "valid-seal")

    assert :ok = TTM.Trace.append(record)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :unverified)) == [
             %{record: record, verification_status: :unverified, verification_error: nil}
           ]

    assert EnvelopeIntegrity.calls() == []
  end

  test "stream_envelopes marks verified records as verified" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    valid = record("env-verified", "s1", "s2", seal: "valid-seal")

    assert :ok = TTM.Trace.append(valid)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :verified)) == [
             %{record: valid, verification_status: :verified, verification_error: nil}
           ]

    assert EnvelopeIntegrity.calls() == [{"valid-seal", valid}]
  end

  test "stream_envelopes marks failed verification as failed" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    failed = record("env-failed", "s1", "s2", seal: "broken-seal")

    assert :ok = TTM.Trace.append(failed)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :failed)) == [
             %{record: failed, verification_status: :failed, verification_error: :invalid_seal}
           ]
  end

  test "stream_envelopes marks verifier unavailable records as unknown" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    unknown = record("env-unknown", "s1", "s2", seal: "missing-verifier-seal")

    assert :ok = TTM.Trace.append(unknown)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :unknown)) == [
             %{record: unknown, verification_status: :unknown, verification_error: nil}
           ]
  end

  test "stream_envelopes filters by verified status" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    valid = record("env-filter-1", "s1", "s2", seal: "valid-seal")
    failed = record("env-filter-2", "s2", "s3", seal: "broken-seal")

    assert :ok = TTM.Trace.append(valid)
    assert :ok = TTM.Trace.append(failed)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :verified)) == [
             %{record: valid, verification_status: :verified, verification_error: nil}
           ]

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :failed)) == [
             %{record: failed, verification_status: :failed, verification_error: :invalid_seal}
           ]
  end

  test "stream_envelopes preserves append order" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    first = record("env-order-1", "s1", "s2", seal: "valid-seal")
    second = record("env-order-2", "s2", "s3", seal: "valid-seal")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)

    assert Enum.to_list(TTM.Trace.stream_envelopes(verified: :verified)) == [
             %{record: first, verification_status: :verified, verification_error: nil},
             %{record: second, verification_status: :verified, verification_error: nil}
           ]
  end

  test "stream_envelopes respects existing TraceQuery filters" do
    Application.put_env(:ttm, :trace_integrity, EnvelopeIntegrity)
    EnvelopeIntegrity.reset!()

    first = record("env-query-1", "s1", "s2", seal: "valid-seal")
    second = record("env-query-2", "s2", "s3", lane: "shadow", seal: "valid-seal")

    third =
      record("env-query-3", "s3", "s4", seal: "valid-seal") |> Map.put(:thread_id, "thread-2")

    assert :ok = TTM.Trace.append(first)
    assert :ok = TTM.Trace.append(second)
    assert :ok = TTM.Trace.append(third)

    assert Enum.to_list(
             TTM.Trace.stream_envelopes(
               thread_id: "thread-1",
               lane: "main",
               limit: 1,
               verified: :verified
             )
           ) == [%{record: first, verification_status: :verified, verification_error: nil}]
  end

  test "external integrity returns not configured when verifier is absent" do
    Application.put_env(:ttm, :trace_integrity, TTM.Trace.ExternalIntegrity)
    Application.delete_env(:ttm, :trace_verify_mfa)

    assert {:error, :verify_not_configured} =
             TTM.Trace.verify("some-seal", record("t-1", "s1", "s2"))
  end

  test "external integrity can call configured verify mfa" do
    Application.put_env(:ttm, :trace_integrity, TTM.Trace.ExternalIntegrity)
    Application.put_env(:ttm, :trace_verify_mfa, {VerifyBridge, :verify})

    assert :ok = TTM.Trace.verify("valid-seal", record("t-1", "s1", "s2"))

    assert {:error, :invalid_seal} =
             TTM.Trace.verify("broken-seal", record("t-1", "s1", "s2"))
  end

  test "reset is disabled unless explicitly allowed" do
    Application.put_env(:ttm, :allow_trace_reset, false)

    assert {:error, :reset_disabled} = TTM.Trace.reset!()
  end

  test "store reset functions are also disabled unless explicitly allowed" do
    Application.put_env(:ttm, :allow_trace_reset, false)
    Application.put_env(:ttm, :trace_dets_path, dets_path())

    assert {:error, :reset_disabled} = TTM.Trace.InMemoryStore.reset!()
    assert {:error, :reset_disabled} = TTM.Trace.DetsStore.reset!()
  end

  test "disabled store reset does not erase trace records" do
    protected = record("protected-reset", "s1", "s2")

    assert :ok = TTM.Trace.append(protected)
    Application.put_env(:ttm, :allow_trace_reset, false)

    assert {:error, :reset_disabled} = TTM.Trace.InMemoryStore.reset!()
    assert Enum.to_list(TTM.Trace.stream()) == [protected]
  end

  defp dets_path do
    Path.join(System.tmp_dir!(), "ttm_trace_test_store.dets")
  end

  defp record(transition_id, from_state_ref, to_state_ref, extra \\ []) do
    base = %{
      thread_id: "thread-1",
      transition_id: transition_id,
      ts: "2026-04-23T00:00:00Z",
      from_state_ref: from_state_ref,
      to_state_ref: to_state_ref,
      admissibility: "rule:v1",
      confidence: 0.9,
      lane: "main",
      seal: "seal-#{transition_id}"
    }

    Enum.into(extra, base)
  end
end

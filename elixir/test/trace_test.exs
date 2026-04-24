defmodule TTM.TraceTest do
  use ExUnit.Case, async: false

  defmodule CapturingStore do
    @moduledoc false

    @agent __MODULE__.Agent

    def append(record) do
      ensure_started()
      Agent.update(@agent, fn records -> [record | records] end)
      :ok
    end

    def stream(_opts) do
      ensure_started()
      @agent |> Agent.get(&Enum.reverse/1) |> Stream.map(& &1)
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

# チーム開発ルール

このリポジトリは開発メンバー4人で運用します。講師の先生は必要に応じてレビューに参加します。

## 1. 開発の基本方針

- **1つの作業につき原則1つのIssue**を作成し、目的・やること・完了条件を明確にします。
- Issueの**Assignees**で担当者を設定します。未決定なら空欄でも構いません。
- GitHub Projectsで進捗を共有し、作業前後にステータスを更新します。
- `main`への直接pushはせず、Pull Request（PR）を通して変更を反映します。
- 迷ったことや仕様変更はIssueやPRに記録し、チームで確認します。

## 2. GitHub ProjectsとIssueの進め方

このリポジトリのIssueは、Projectに設定済みの「Auto-add to project」（`is:issue is:open`）により、条件に一致すると自動追加されます。**PR自体はこのフィルターの対象外**です。

| Status | 意味 | 変更するタイミング |
| --- | --- | --- |
| Todo | 未着手 | Issueを作成したとき |
| In Progress | 作業中 | 担当者が着手したとき |
| In Review | レビュー待ち | 作業用PRを作り、レビューを依頼したとき |
| Done | 完了 | PRのマージなどで完了条件を満たし、Issueを閉じたとき |

Project「[朝課外キャンセル界隈 - 開発管理](https://github.com/users/New119/projects/4)」には、上記4つのStatus、Priority（P0 / P1 / P2）、Due date（Date型）を設定しています。担当者はIssueのAssigneesで管理します。

- P0：他の作業の前提・最優先の作業。
- P1：MVPを完成させるための作業。
- P2：後続の改善。
- 担当者と期限はチームで合意してから設定します。未定なら空欄のままにします。
- Issue本文にも優先度と前提Issueを記載し、Projectの値とそろえます。

**運用の例：**

1. Issueを作成し、担当者を決めます（Todo）。
2. 担当者が着手したら、ProjectでIn Progressにします。
3. PRを作ってレビューを依頼したら、**元のIssue**をIn Reviewにします。
4. 承認後にPRをマージし、Issueが閉じたことを確認します（Done）。
5. Issueが自動でDoneにならない場合は、Projectのワークフロー「Item closed → Done」を有効にするか、手動で更新します。

自動化の有効・無効はGitHub Projectsの**Workflows**で確認します。2026-11-13時点では、Item added → Todo、Item closed → Done、Done → Issueクローズが有効です。**Doneへ移すとIssueも閉じるため、完了条件を満たしたことを先に確認します。** PR linked → In Progressも有効なので、レビュー依頼時は元Issueを手動でIn Reviewへ移します。

## 3. ブランチの使い分け

- `main`：レビュー済みのコードを置く保護対象ブランチ。
- `feature/機能名`：新機能（例：`feature/card-display`）。
- `fix/修正内容`：不具合修正（例：`fix/card-layout`）。
- `docs/内容`：文章やREADME（例：`docs/readme-members`）。
- `chore/内容`：開発環境・設定など。

担当者ごとに固定ブランチを作るのではなく、**作業ごとに最新の`main`からブランチを作ります。**

```bash
git switch main
git pull origin main
git switch -c feature/card-display

# 変更を確認してから
git add .
git commit -m "feat: カードの表示機能を追加"
git push -u origin feature/card-display
```

push後はGitHubの画面で`main`宛てのPRを作ります。変更が競合した場合は、チームに相談して解消します。

## 4. Pull Requestの出し方とレビュー

1. PRテンプレートに変更内容・関連Issue・動作確認を記入します。
2. **そのPRのマージでIssueの作業がすべて完了する場合**は、PR本文に `Closes #Issue番号` を記載します（例：`Closes #12`）。
3. まだ作業が残る場合は、Issueを閉じないよう `Refs #Issue番号` と記載します。
4. PRの`Files changed`を確認し、別のメンバーにレビューを依頼します。
5. `main`には有効な`main-protection`ルールがあり、**別のメンバー1人以上の承認が必要**です。PR作成者自身の承認はカウントされません。
6. 承認され、必要な確認が済んだらPRをマージします。

`Closes #番号` などでリンクされたIssueは、既定のGitHub設定ではPRがデフォルトブランチにマージされると自動で閉じます。リポジトリの自動クローズ設定が無効な場合は手動で閉じます。

## 5. コミットメッセージ

- `feat: ○○を追加`：新機能
- `fix: ○○を修正`：バグ修正
- `docs: ○○を更新`：文書
- `refactor: ○○を整理`：機能を変えないコード改善
- `chore: ○○を設定`：環境や設定

## 6. PRを出す前の確認

- 変更内容を自分で読み直し、関連するIssueと内容が一致するか確認する。
- 実施したテスト・手動での動作確認と、未確認の部分を書く。
- パスワード、APIキー、`.env` などの秘密情報をコミットしない。
- 大きな変更は分けて、チームがレビューしやすいサイズにする。

## 7. 開発環境について

Ruby / Railsのバージョン、セットアップ方法、テストコマンドは、アプリの仕様と開発環境が決まり次第追記します。

## 8. PM・Codex・チームの役割

- PMはIssue・Projects・PRの状態を整理し、目的・作業内容・完了条件・優先度・依存関係を明確にします。
- コードの実装と修正は原則としてCodexが作業ブランチ上で行い、動作確認結果をPRへ記録します。
- ゲーム仕様・技術構成・担当者・期限の未決定事項はチームで決定します。AIは推測で決定しません。
- 人間のチームメンバーがレビュー承認とマージ判断を行います。AIは人間の承認を代行しません。
- main保護を維持し、既存データの削除や重要な設定変更は事前にチームへ確認します。
